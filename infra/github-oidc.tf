# ---------------------------------------------------------------------------
# GitHub Actions deployment policy
#
# Attaches an inline policy to the manually-created GitHubActionDeployRole
# granting exactly the permissions needed to deploy this Terraform stack.
# The role already exists, so we can reference it by name directly and avoid
# an IAM read during planning.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = var.manage_github_actions_role_policy ? 1 : 0

  name = "ubika-infra-deploy-policy"
  role = "GitHubActionDeployRole"

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
        Sid    = "EC2VPC"
        Effect = "Allow"
        Action = [
          "ec2:*",
        ]
        Resource = "*"
      },
      # ── IAM – scoped to roles/policies this stack creates ──────────────
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
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
        ]
        Resource = "arn:aws:iam::*:role/${var.name}-*"
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
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:*",
        ]
        Resource = "*"
      },
    ]
  })
}
