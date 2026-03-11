variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. production, staging)."
  type        = string
  default     = "production"
}

variable "name" {
  description = "Standard name prefix used in resource naming."
  type        = string
  default     = "genai-gateway"
}

variable "manage_github_actions_role_policy" {
  description = "Whether Terraform should manage the inline policy on the manually-created GitHubActionDeployRole. Keep false for normal CI/CD runs; enable only for one-time bootstrap updates."
  type        = bool
  default     = false
}

variable "github_actions_role_name" {
  description = "Name of the manually-created IAM role used by GitHub Actions OIDC."
  type        = string
  default     = "GitHubActionDeployRole"
}
