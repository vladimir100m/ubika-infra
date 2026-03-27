data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name}-ecs-scale-toggle-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "ECSUpdateService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ApplicationAutoScaling"
    actions = [
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DescribeScalableTargets",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name}-ecs-scale-toggle"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}-ecs-scale-toggle"
  retention_in_days = 14
}

resource "aws_lambda_function" "scale_toggle" {
  function_name    = "${var.name}-ecs-scale-toggle"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout_seconds
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      ECS_CLUSTER    = var.ecs_cluster_name
      ECS_SERVICE    = var.ecs_service_name
      MAX_TASK_COUNT = tostring(var.max_task_count)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}
