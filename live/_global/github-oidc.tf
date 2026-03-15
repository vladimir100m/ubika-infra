# ---------------------------------------------------------------------------
# GitHub Actions deployment policy
#
# Attaches an inline policy to the manually-created GitHubActionDeployRole
# granting exactly the permissions needed to deploy this Terraform stack.
# The role already exists, so we reference it by name directly.
#
# This resource is opt-in (manage_github_actions_role_policy = false by
# default) to avoid the deploy role trying to modify itself during normal runs.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = var.manage_github_actions_role_policy ? 1 : 0

  name = "ubika-infra-deploy-policy"
  role = var.github_actions_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── S3 – Terraform state bucket ────────────────────────────────────
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = [
          "arn:aws:s3:::terraform-ubika-*",
          "arn:aws:s3:::terraform-ubika-*/*",
        ]
      },
      # ── EC2 / VPC ──────────────────────────────────────────────────────
      {
        Sid      = "EC2VPC"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      # ── IAM – scoped to roles this stack creates ────────────────────────
      {
        Sid    = "IAMScopedToStack"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = [
          "arn:aws:iam::703544859494:role/cdk-*",
          "arn:aws:iam::703544859494:role/genai-gateway-*",
          "arn:aws:iam::703544859494:policy/genai-gateway-*",
        ]
      },
      # ── iam:PassRole – scoped to VPC Flow Logs only ─────────────────────
      {
        Sid    = "IAMPassRoleToVPCFlowLogs"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:aws:iam::703544859494:role/genai-gateway-*",
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "vpc-flow-logs.amazonaws.com"
          }
        }
      },
      # ── iam:PassRole – ECS task and execution roles ─────────────────────
      {
        Sid    = "IAMPassRoleToECSTasks"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:aws:iam::703544859494:role/genai-gateway-*",
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      # ── CloudWatch Logs ────────────────────────────────────────────────
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:ListTagsLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:TagResource",
          "logs:ListTagsForResource",
        ]
        Resource = "*"
      },
      # ── Route 53 ───────────────────────────────────────────────────────
      {
        Sid      = "Route53"
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = "*"
      },
    ]
  })
}
