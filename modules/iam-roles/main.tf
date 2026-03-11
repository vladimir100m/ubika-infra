###############################################################################
# modules/iam-roles
#
# Provisions the two standard ECS IAM roles every Fargate service needs.
#
#  Task EXECUTION Role – used by the ECS agent to:
#    - Pull container images from ECR
#    - Write logs to CloudWatch Logs
#    - Read secrets from Secrets Manager at task start-up
#
#  Task Role – used by the RUNNING container to call AWS APIs:
#    - Bedrock, S3, DynamoDB, SQS, etc.
#    - Scoped strictly to what the application needs at runtime
#
# NEVER merge these two roles – their trust principals and permission scopes
# are fundamentally different.
#
# Reusable for: any ECS service. Pass extra_secrets_arns to extend the
# execution role, and task_role_policy_arns to extend the task role.
###############################################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── Task Execution Role ──────────────────────────────────────────────────────
resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${var.name}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_extra" {
  count = length(var.extra_secrets_arns) > 0 ? 1 : 0

  statement {
    sid       = "SecretsManagerRead"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.extra_secrets_arns
  }
}

resource "aws_iam_policy" "execution_extra" {
  count  = length(var.extra_secrets_arns) > 0 ? 1 : 0
  name   = "${var.name}-ecs-execution-extra-policy"
  policy = data.aws_iam_policy_document.execution_extra[0].json
}

resource "aws_iam_role_policy_attachment" "execution_extra" {
  count      = length(var.extra_secrets_arns) > 0 ? 1 : 0
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution_extra[0].arn
}

resource "aws_iam_role_policy_attachment" "execution_extra_managed" {
  for_each   = toset(var.extra_execution_role_policy_arns)
  role       = aws_iam_role.execution.name
  policy_arn = each.value
}

# ── Task Role ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${var.name}-ecs-task-role"
  }
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each   = toset(var.task_role_policy_arns)
  role       = aws_iam_role.task.name
  policy_arn = each.value
}
