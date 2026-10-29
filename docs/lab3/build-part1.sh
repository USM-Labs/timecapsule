#!/bin/bash
# ЛР3, Часть 1 (задания 2-5): сеть timecapsule-dev-vpc, Security Group и три сервера.
# Все ресурсы получают Name и обязательные теги. Идентификаторы сохраняются в ids.env.
set -euo pipefail
export AWS_REGION=eu-central-1 AWS_PAGER=""
X=16
MYIP=$(curl -s https://checkip.amazonaws.com)/32
KEY=maxsplavski-keypair
IDS="$(dirname "$0")/ids.env"
: > "$IDS"
save() { echo "$1=$2" >> "$IDS"; echo "    $1=$2"; }
tags() { echo "{Key=Name,Value=$1},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=maxsplavski},{Key=Lab,Value=lab3}"; }
spec() { echo "ResourceType=$1,Tags=[$(tags "$2")]"; }

echo "==> VPC 10.$X.0.0/16"
VPC=$(aws ec2 create-vpc --cidr-block 10.$X.0.0/16 --tag-specifications "$(spec vpc timecapsule-dev-vpc)" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames '{"Value":true}'
save VPC $VPC

echo "==> Подсети"
subnet() { aws ec2 create-subnet --vpc-id $VPC --availability-zone $2 --cidr-block $3 \
    --tag-specifications "$(spec subnet timecapsule-dev-$1)" --query Subnet.SubnetId --output text; }
PUB_A=$(subnet public-a  eu-central-1a 10.$X.0.0/24);  save PUB_A $PUB_A
PUB_B=$(subnet public-b  eu-central-1b 10.$X.1.0/24);  save PUB_B $PUB_B
PRV_A=$(subnet private-a eu-central-1a 10.$X.10.0/24); save PRV_A $PRV_A
PRV_B=$(subnet private-b eu-central-1b 10.$X.11.0/24); save PRV_B $PRV_B

echo "==> Internet Gateway и таблицы маршрутов"
IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(spec internet-gateway timecapsule-dev-igw)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
save IGW $IGW
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "$(spec route-table timecapsule-dev-public-rt)" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
PRV_RT=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "$(spec route-table timecapsule-dev-private-rt)" --query RouteTable.RouteTableId --output text)
for s in $PUB_A $PUB_B; do aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $s >/dev/null; \
    aws ec2 modify-subnet-attribute --subnet-id $s --map-public-ip-on-launch; done
for s in $PRV_A $PRV_B; do aws ec2 associate-route-table --route-table-id $PRV_RT --subnet-id $s >/dev/null; done
save PUB_RT $PUB_RT; save PRV_RT $PRV_RT

echo "==> Security Group"
sg() { aws ec2 create-security-group --vpc-id $VPC --group-name timecapsule-dev-$1 --description "$2" \
    --tag-specifications "$(spec security-group timecapsule-dev-$1)" --query GroupId --output text; }
SG_BASTION=$(sg bastion-sg "SSH access to bastion"); save SG_BASTION $SG_BASTION
SG_WEB=$(sg web-sg "HTTP from internet, SSH from bastion"); save SG_WEB $SG_WEB
SG_DB=$(sg db-sg "PostgreSQL from web-sg, SSH from bastion"); save SG_DB $SG_DB
aws ec2 authorize-security-group-ingress --group-id $SG_BASTION --ip-permissions \
    "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MYIP,Description=My IP}]" >/dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_WEB --ip-permissions \
    "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP from anywhere}]" \
    "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$SG_BASTION,Description=SSH from bastion}]" >/dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_DB --ip-permissions \
    "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$SG_WEB,Description=PostgreSQL from web-sg}]" \
    "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$SG_BASTION,Description=SSH from bastion}]" >/dev/null

echo "==> Экземпляры"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
run() { # $1 роль, $2 подсеть, $3 SG, $4 public ip true/false, $5 user data file (опционально)
    local ud=(); [ -n "${5:-}" ] && ud=(--user-data "file://$5")
    aws ec2 run-instances --image-id $AMI --instance-type t3.micro --key-name $KEY ${ud[@]+"${ud[@]}"} \
        --network-interfaces "DeviceIndex=0,SubnetId=$2,Groups=$3,AssociatePublicIpAddress=$4" \
        --tag-specifications "$(spec instance timecapsule-dev-$1)" "$(spec volume timecapsule-dev-$1)" \
        --query 'Instances[0].InstanceId' --output text; }
UD=$(mktemp)
cat > "$UD" <<'EOF'
#!/bin/bash
dnf -y install nginx
echo "<h1>$(hostname)</h1><p>$(hostname -I)</p>" > /usr/share/nginx/html/index.html
systemctl enable --now nginx
EOF
BASTION=$(run bastion $PUB_B $SG_BASTION true);  save BASTION $BASTION
WEB=$(run web $PUB_A $SG_WEB true "$UD");        save WEB $WEB
DB=$(run db $PRV_A $SG_DB false);                save DB $DB
rm -f "$UD"
aws ec2 wait instance-running --instance-ids $BASTION $WEB $DB
echo "Готово."
