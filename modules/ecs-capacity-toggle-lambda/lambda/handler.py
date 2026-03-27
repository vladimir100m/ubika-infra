"""
Manually invoked Lambda: scale ECS service to stop (0/0) or start (1/1) tasks.

Event (direct invoke): {"mode": "stop"} | {"mode": "start"}
Aliases: stop/down/0 and start/up/1
"""

import json
import os

import boto3

ecs = boto3.client("ecs")
aas = boto3.client("application-autoscaling")

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_SERVICE = os.environ["ECS_SERVICE"]
MAX_TASK_COUNT = int(os.environ.get("MAX_TASK_COUNT", "4"))

RESOURCE_ID = f"service/{ECS_CLUSTER}/{ECS_SERVICE}"


def handler(event, context):
    payload = _parse_event(event)
    mode = (payload.get("mode") or payload.get("action") or "").lower()

    if mode in ("stop", "down", "0", "pause"):
        desired, min_cap = 0, 0
    elif mode in ("start", "up", "1", "resume"):
        desired, min_cap = 1, 1
    else:
        return _response(
            400,
            {
                "error": "Missing or invalid mode",
                "hint": 'Use {"mode":"stop"} or {"mode":"start"}',
            },
        )

    if MAX_TASK_COUNT < min_cap:
        return _response(
            400,
            {
                "error": "MAX_TASK_COUNT is less than requested min_capacity",
                "max_task_count": MAX_TASK_COUNT,
                "min_capacity": min_cap,
            },
        )

    aas.register_scalable_target(
        ServiceNamespace="ecs",
        ResourceId=RESOURCE_ID,
        ScalableDimension="ecs:service:DesiredCount",
        MinCapacity=min_cap,
        MaxCapacity=max(MAX_TASK_COUNT, min_cap),
    )

    ecs.update_service(
        cluster=ECS_CLUSTER,
        service=ECS_SERVICE,
        desiredCount=desired,
    )

    return _response(
        200,
        {
            "ok": True,
            "cluster": ECS_CLUSTER,
            "service": ECS_SERVICE,
            "desiredCount": desired,
            "minCapacity": min_cap,
            "maxCapacity": max(MAX_TASK_COUNT, min_cap),
        },
    )


def _parse_event(event):
    if not event:
        return {}
    if isinstance(event, str):
        try:
            return json.loads(event)
        except json.JSONDecodeError:
            return {}
    return event


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "body": json.dumps(body),
    }
