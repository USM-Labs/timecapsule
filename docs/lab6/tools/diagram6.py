"""Lab 6, task 7: TimeCapsule behind an ALB with an Auto Scaling group and sessions in DynamoDB."""
import sys

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2Instance, EC2AutoScaling, EC2Ami
from diagrams.aws.general import Users
from diagrams.aws.network import ElbApplicationLoadBalancer, InternetGateway, Route53HostedZone
from diagrams.aws.security import IAMRole
from diagrams.aws.database import RDSPostgresqlInstance, DynamodbTable
from diagrams.aws.integration import Eventbridge
from diagrams.aws.management import Cloudwatch
from diagrams.aws.storage import SimpleStorageServiceS3BucketWithObjects
from diagrams.onprem.client import Client
from diagrams.onprem.vcs import Github

out = sys.argv[1]


def group(color, style="solid", bg="white"):
    return {"pencolor": color, "style": style, "bgcolor": bg, "fontcolor": color, "fontsize": "13",
            "fontname": "Helvetica-Bold", "labeljust": "l", "penwidth": "2", "margin": "14"}


graph = {"pad": "0.4", "nodesep": "0.5", "ranksep": "0.9", "fontname": "Helvetica", "splines": "spline",
         "newrank": "true"}
node = {"fontname": "Helvetica", "fontsize": "11"}
PUB = ("#7aa116", "solid", "#f2f6e8")
PRIV = ("#147eba", "solid", "#e6f2f8")

with Diagram("TimeCapsule — Lab 6: ALB + Auto Scaling, sessions in DynamoDB (timecapsule-dev, eu-central-1)",
             filename=out, outformat="png", show=False, direction="LR", graph_attr=graph, node_attr=node):
    users = Users("Users\n(browser)")
    with Cluster("Developer", graph_attr=group("#545b64", "dashed")):
        laptop = Client("My computer\ngit push · ssh (ProxyJump)")
    github = Github("GitHub\nUSM-Labs/timecapsule")

    with Cluster("AWS Cloud · Region eu-central-1", graph_attr=group("#232f3e")):
        with Cluster("Regional services (outside the VPC)", graph_attr=group("#545b64", "dashed")):
            ddb = DynamodbTable("timecapsule-dev-sessions\nkey id · On-demand · TTL expires")
            bucket = SimpleStorageServiceS3BucketWithObjects("timecapsule-dev-uploads-maxsplavski\nuploads/")
            role = IAMRole("timecapsule-dev-app-role\nS3 uploads/* + timecapsule-dev-app-sessions\n(Get/Put/Update/DeleteItem)")
            ami = EC2Ami("AMI timecapsule-dev-app-lab6\n→ launch template\ntimecapsule-dev-app-lt")
            cw = Cloudwatch("CloudWatch\nRequestCountPerTarget\nAlarmHigh / AlarmLow")
            sched = Eventbridge("Scheduler\nRDS stop 23:00")

        with Cluster("timecapsule-dev-vpc  10.16.0.0/16", graph_attr=group("#8c4fff")):
            igw = InternetGateway("timecapsule-dev-igw")
            zone = Route53HostedZone("private zone timecapsule.internal\ndb CNAME → RDS endpoint")
            alb = ElbApplicationLoadBalancer("timecapsule-dev-alb\nInternet-facing · HTTP:80\nSG alb-sg: 80 from 0.0.0.0/0\n→ timecapsule-dev-tg (GET /health)")
            with Cluster("Auto Scaling group timecapsule-dev-asg  (min 2 · desired 2 · max 4)\ntarget tracking 50 requests/target · ELB health checks",
                         graph_attr=group("#ed7100", "dashed", "#fff7ef")):
                with Cluster("eu-central-1a · public-a 10.16.0.0/24", graph_attr=group(*PUB)):
                    a1 = EC2Instance("app (ASG)\nnginx + PHP-FPM")
                    a2 = EC2Instance("app (scale-out)")
                with Cluster("eu-central-1b · public-b 10.16.1.0/24", graph_attr=group(*PUB)):
                    b1 = EC2Instance("app (ASG)\nnginx + PHP-FPM")
                    b2 = EC2Instance("app (scale-out)")
                asg = EC2AutoScaling("SG web-sg: 80 only from alb-sg\n22 from bastion-sg")
            with Cluster("eu-central-1b · public-b", graph_attr=group(*PUB)):
                bastion = EC2Instance("timecapsule-dev-bastion\n(SSH 22 from my IP)")
            with Cluster("eu-central-1a · private-a 10.16.10.0/24", graph_attr=group(*PRIV)):
                rds = RDSPostgresqlInstance("timecapsule-dev-rds\nPostgreSQL 16.15\nrds-sg: 5432 from web-sg")

    users >> Edge(label="HTTP :80 DNS name of ALB", color="#1a73e8", penwidth="2") >> igw >> Edge(color="#1a73e8", penwidth="2") >> alb
    for s in (a1, a2, b1, b2):
        alb >> Edge(color="#1a73e8") >> s
    asg >> Edge(label="every server: SQL :5432 TLS", color="#147eba", penwidth="2") >> rds
    asg >> Edge(label="every server: session Get/PutItem", color="#c925d1", penwidth="2") >> ddb
    asg >> Edge(label="S3 Put/Delete", color="#7aa116") >> bucket
    users >> Edge(label="GET presigned URL", color="#1a73e8", style="bold") >> bucket
    asg >> Edge(label="DNS", style="dotted") >> zone
    role - Edge(label="instance profile", color="#dd344c", style="dashed") - asg
    ami >> Edge(label="launches from", color="#ed7100", style="dashed") >> asg
    cw >> Edge(label="alarm → desired 2↔4", color="#e7157b", style="dashed") >> asg
    alb >> Edge(label="metric", color="#7f7f7f", style="dotted") >> cw
    sched >> Edge(color="#e7157b", style="dashed") >> rds
    laptop >> Edge(label="git push", color="#2da44e") >> github
    laptop >> Edge(label="ssh", color="#ed7100") >> bastion
