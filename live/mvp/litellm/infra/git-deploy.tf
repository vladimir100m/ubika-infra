# GitHub deploy key: clone private repo on first boot (private key in SSM, read by user-data).
resource "tls_private_key" "github_deploy" {
  count = var.use_git_clone ? 1 : 0

  algorithm = "ED25519"
}

resource "aws_ssm_parameter" "github_deploy_private_key" {
  count = var.use_git_clone ? 1 : 0

  name        = "/${var.name}/github-deploy-key"
  description = "OpenSSH private key for GitHub deploy (repo clone on EC2)"
  type        = "SecureString"
  value       = tls_private_key.github_deploy[0].private_key_openssh
}

data "aws_iam_policy_document" "ssm_github_deploy_key" {
  count = var.use_git_clone ? 1 : 0

  statement {
    sid = "ReadGitHubDeployKey"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [aws_ssm_parameter.github_deploy_private_key[0].arn]
  }
}

resource "aws_iam_role_policy" "ssm_github_deploy_key" {
  count = var.use_git_clone ? 1 : 0

  name   = "${var.name}-ssm-github-deploy-key"
  role   = module.ec2_ssm.iam_role_name
  policy = data.aws_iam_policy_document.ssm_github_deploy_key[0].json
}
