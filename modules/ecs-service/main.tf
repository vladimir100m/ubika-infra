# ---------------------------------------------------------------------------
# Module: ecs-service
#
# Provisions a single ECS service with its Task Definition, ALB listener rule,
# target group, auto-scaling, and CloudWatch alarms.
# Intended to be called once per application under live/<env>/services/<app>/.
# ---------------------------------------------------------------------------

# Placeholder – implement when adding the first ECS service.
# Expected resources:
#   - aws_ecs_task_definition
#   - aws_ecs_service
#   - aws_lb_target_group
#   - aws_lb_listener_rule
#   - aws_appautoscaling_target + aws_appautoscaling_policy
#   - aws_cloudwatch_metric_alarm
