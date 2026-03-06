
import json
import os

import boto3


def handler(event, context):
    region         = os.environ["REGION"]
    cluster_arn    = os.environ["ECS_CLUSTER_ARN"]
    task_def_arn   = os.environ["ECS_TASK_DEF_ARN"]
    subnet_id      = os.environ["ECS_SUBNET_ID"]
    security_grp   = os.environ["ECS_SECURITY_GRP_ID"]

    ecs = boto3.client("ecs", region_name=region)

    response = ecs.run_task(
        cluster        = cluster_arn,
        taskDefinition = task_def_arn,
        launchType     = "FARGATE",
        networkConfiguration = {
            "awsvpcConfiguration": {
                "subnets":         [subnet_id],
                "securityGroups":  [security_grp],
                # Public subnet — no NAT Gateway needed
                "assignPublicIp":  "ENABLED",
            }
        },
        count = 1,
    )

    tasks   = response.get("tasks", [])
    failures = response.get("failures", [])

    if failures:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message":  "ECS RunTask failed",
                "failures": failures,
                "region":   region,
            }),
        }

    task_arn = tasks[0]["taskArn"] if tasks else "unknown"

    return {
        "statusCode": 202,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message":  f"ECS task dispatched in {region}",
            "region":   region,
            "task_arn": task_arn,
        }),
    }
