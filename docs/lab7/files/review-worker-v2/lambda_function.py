import json


def lambda_handler(event, context):
    # Raw message delivery is on: the SQS body is the review JSON itself.
    for record in event["Records"]:
        review = json.loads(record["body"])
        text = review.get("text") or "(no text)"
        print(f'{review["id"]}: {review["rating"]}/5 {text[:20]}')
