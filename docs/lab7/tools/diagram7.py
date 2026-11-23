"""Lab 7, task 10: TimeCapsule with background work in AWS Lambda (SNS + SQS + EventBridge Scheduler)."""
import sys

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2Instance, EC2AutoScaling, Lambda
from diagrams.aws.general import Users, User
from diagrams.aws.network import ElbApplicationLoadBalancer, InternetGateway
from diagrams.aws.security import IAMRole
from diagrams.aws.database import RDSPostgresqlInstance, DynamodbTable
from diagrams.aws.integration import Eventbridge, SimpleNotificationServiceSns, SimpleQueueServiceSqsQueue
from diagrams.aws.management import Cloudwatch
from diagrams.aws.storage import SimpleStorageServiceS3BucketWithObjects

out = sys.argv[1]


def group(color, style="solid", bg="white"):
    return {"pencolor": color, "style": style, "bgcolor": bg, "fontcolor": color, "fontsize": "13",
            "fontname": "Helvetica-Bold", "labeljust": "l", "penwidth": "2", "margin": "14"}


graph = {"pad": "0.4", "nodesep": "0.5", "ranksep": "1.0", "fontname": "Helvetica", "splines": "spline", "newrank": "true"}
node = {"fontname": "Helvetica", "fontsize": "11"}
PUB = ("#7aa116", "solid", "#f2f6e8")
PRIV = ("#147eba", "solid", "#e6f2f8")

with Diagram("TimeCapsule — Lab 7: e-mail and capsule opening in AWS Lambda (SNS + SQS, eu-central-1)",
             filename=out, outformat="png", show=False, direction="LR", graph_attr=graph, node_attr=node):
    users = Users("Users\n(browser)")
    owner = User("Capsule owner\nmox7.sp1avsk1@gmail.com")

    with Cluster("AWS Cloud · Region eu-central-1", graph_attr=group("#232f3e")):
        with Cluster("Regional services (outside the VPC)", graph_attr=group("#545b64", "dashed")):
            topic = SimpleNotificationServiceSns("SNS timecapsule-dev-events\ncapsule.sealed · capsules.opened")
            queue = SimpleQueueServiceSqsQueue("SQS timecapsule-dev-mail\nvisibility 120 s · 4 days\nmaxReceiveCount 3")
            dlq = SimpleQueueServiceSqsQueue("SQS timecapsule-dev-mail-dlq\n14 days")
            sched = Eventbridge("Scheduler\ntimecapsule-dev-open-capsules\nrate(1 minute)")
            ddb = DynamodbTable("timecapsule-dev-sessions")
            bucket = SimpleStorageServiceS3BucketWithObjects("timecapsule-dev-uploads-maxsplavski")
            role = IAMRole("timecapsule-dev-app-role\n+ timecapsule-dev-app-events\n(sns:Publish on the topic)")
            cw = Cloudwatch("CloudWatch Logs\n/aws/lambda/*")

        with Cluster("timecapsule-dev-vpc  10.16.0.0/16", graph_attr=group("#8c4fff")):
            igw = InternetGateway("timecapsule-dev-igw")
            alb = ElbApplicationLoadBalancer("timecapsule-dev-alb\nHTTP:80")
            with Cluster("Auto Scaling group timecapsule-dev-asg (2-4)\nAMI timecapsule-dev-app-lab7 · LT v2",
                         graph_attr=group("#ed7100", "dashed", "#fff7ef")):
                with Cluster("public-a / public-b", graph_attr=group(*PUB)):
                    app1 = EC2Instance("app (1a)\nnginx + PHP-FPM")
                    app2 = EC2Instance("app (1b)")
                asg = EC2AutoScaling("web-sg: 80 from alb-sg")
            with Cluster("private-a / private-b  ·  SG timecapsule-dev-lambda-sg (out: 5432 to RDS only)",
                         graph_attr=group(*PRIV)):
                mailer = Lambda("timecapsule-dev-mailer\nbatch 5 · max concurrency 2\nReportBatchItemFailures")
                opener = Lambda("timecapsule-dev-opener\nasync · retries 0\ndestination OnSuccess → SNS")
                rds = RDSPostgresqlInstance("timecapsule-dev-rds (1a)\nuser timecapsule_worker\nnotifications UNIQUE(capsule_id, kind)")

    users >> Edge(label="HTTP", color="#1a73e8", penwidth="2") >> igw >> Edge(color="#1a73e8", penwidth="2") >> alb
    alb >> Edge(color="#1a73e8") >> app1
    alb >> Edge(color="#1a73e8") >> app2
    asg >> Edge(label="SQL", color="#147eba") >> rds
    asg >> Edge(label="sessions", color="#c925d1", style="dashed") >> ddb
    asg >> Edge(label="files", color="#7aa116", style="dashed") >> bucket
    role - Edge(style="dashed", color="#dd344c") - asg
    asg >> Edge(label="1. Publish capsule.sealed\n(answer at once)", color="#e7157b", penwidth="2.5") >> topic
    topic >> Edge(label="2. raw, filter: sealed or opened count>0", color="#e7157b", penwidth="2.5") >> queue
    queue >> Edge(label="3. poll (Lambda service)", color="#e7157b", penwidth="2.5") >> mailer
    queue >> Edge(label="after 3 receives", color="#d13212", style="dashed") >> dlq
    mailer >> Edge(label="4. INSERT ... ON CONFLICT DO NOTHING", color="#147eba", penwidth="2") >> rds
    sched >> Edge(label="every minute (async)", color="#ff4f8b", penwidth="2") >> opener
    opener >> Edge(label="UPDATE ... RETURNING", color="#147eba", penwidth="2") >> rds
    opener >> Edge(label="invocation record\n(Lambda service, not the code)", color="#ff4f8b", style="dashed", penwidth="2") >> topic
    topic >> Edge(label="e-mail: only capsules.opened, count>0", color="#ff9900", penwidth="2") >> owner
    mailer >> Edge(style="dotted", color="#7f7f7f") >> cw
