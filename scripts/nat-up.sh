#!/bin/bash
# Временный NAT Gateway для приватных подсетей timecapsule-dev-vpc.
# Выделяет Elastic IP, создаёт NAT Gateway в public-a, ждёт его готовности
# и добавляет маршрут 0.0.0.0/0 в private-rt. Идентификаторы сохраняются в nat-state.env.
set -euo pipefail

AWS_REGION=eu-central-1
SUBNET_ID=subnet-000f0a18dd06dca47      # timecapsule-dev-public-a
ROUTE_TABLE_ID=rtb-03c425148cd18f92a    # timecapsule-dev-private-rt
STATE_FILE="$(dirname "$0")/nat-state.env"
export AWS_REGION AWS_PAGER=""

tags() { # $1 = значение тега Name
    echo "{Key=Name,Value=$1},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=maxsplavski},{Key=Lab,Value=lab3}"
}

if [ -f "$STATE_FILE" ]; then
    echo "Файл $STATE_FILE уже есть: NAT Gateway, похоже, поднят. Сначала выполните nat-down.sh." >&2
    exit 1
fi

echo "==> Выделяем Elastic IP"
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[$(tags timecapsule-dev-nat-a-eip)]" \
    --query AllocationId --output text)
echo "    $ALLOCATION_ID"
echo "ALLOCATION_ID=$ALLOCATION_ID" > "$STATE_FILE"

echo "==> Создаём NAT Gateway в public-a"
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$SUBNET_ID" --allocation-id "$ALLOCATION_ID" \
    --connectivity-type public \
    --tag-specifications "ResourceType=natgateway,Tags=[$(tags timecapsule-dev-nat-a)]" \
    --query NatGateway.NatGatewayId --output text)
echo "    $NAT_ID"
echo "NAT_ID=$NAT_ID" >> "$STATE_FILE"

echo "==> Ждём, пока NAT Gateway станет available"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

echo "==> Добавляем маршрут 0.0.0.0/0 -> $NAT_ID в private-rt"
aws ec2 create-route --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" --output text >/dev/null

PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --query 'Addresses[0].PublicIp' --output text)
echo "Готово. NAT Gateway $NAT_ID, внешний адрес приватных подсетей: $PUBLIC_IP"
echo "Не забудьте выполнить nat-down.sh: NAT Gateway оплачивается за каждый час."
