
import json
import os
import uuid
from datetime import datetime, timezone

import boto3


def handler(event, context):
    region          = os.environ["REGION"]
    table_name      = os.environ["DYNAMODB_TABLE"]
    sns_topic_arn   = os.environ["SNS_TOPIC_ARN"]
    email           = os.environ["TEST_USER_EMAIL"]
    github_repo_url = os.environ["GITHUB_REPO_URL"]

    # ----------------------------------------------------------------
    # 1. Write to regional DynamoDB
    # ----------------------------------------------------------------
    dynamodb = boto3.resource("dynamodb", region_name=region)
    table    = dynamodb.Table(table_name)

    item = {
        "id":        str(uuid.uuid4()),
        "region":    region,
        "email":     email,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source":    "Lambda-Greeter",
    }
    table.put_item(Item=item)

    # ----------------------------------------------------------------
    # 2. Publish to Unleash live SNS topic (always us-east-1)
    # ----------------------------------------------------------------
    try:
        sns = boto3.client("sns", region_name="us-east-1")  # hardcoded us-east-1
        payload = {
            "email":  email,
            "source": "Lambda",
            "region": region,           # executing region
            "repo":   github_repo_url,
        }
        response = sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(payload),
        )
        print(f"SNS publish successful: {response['MessageId']}")

    except Exception as e:
        print(f"SNS publish FAILED: {str(e)}")  # log but don't fail Lambda
        raise e

    # ----------------------------------------------------------------
    # 3. Return 200 with region
    # ----------------------------------------------------------------
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": f"Hello from {region}!",
            "region":  region,
            "item_id": item["id"],
        }),
    }
