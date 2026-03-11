variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Standard name to be used as prefix on all resources."
  type        = string
  default     = "genai-gateway"
}

variable "vpc_id" {
  description = "If set, use this VPC instead of creating a new one. Leave empty to create a new VPC."
  type        = string
  default     = ""
}

variable "create_vpc_endpoints_in_existing_vpc" {
  description = "If using an existing VPC, set this to true to also create interface/gateway endpoints within it."
  type        = bool
  default     = false
}

variable "disable_outbound_network_access" {
  description = "Whether to disable outbound network access"
  type        = bool
  default     = false
}

variable "manage_github_actions_role_policy" {
  description = "Whether Terraform should manage the inline policy on the manually-created GitHubActionDeployRole. Keep false for normal CI/CD runs; enable only for one-time bootstrap updates."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Deployment environment name (e.g. production, staging). Used in resource tags and naming."
  type        = string
  default     = "production"
}

variable "github_actions_role_name" {
  description = "Name of the manually-created IAM role used by GitHub Actions OIDC."
  type        = string
  default     = "GitHubActionDeployRole"
}
