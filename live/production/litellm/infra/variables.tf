################################################################################
# General
################################################################################
variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "production"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "genai-gateway"
}

variable "aws_account_id" {
  description = "AWS account ID."
  type        = string
  default     = "703544859494"
}

variable "read_bootstrap_remote_state" {
  description = "Whether to read the bootstrap remote state for ALB access-log bucket integration. Set true after bootstrap layer is applied."
  type        = bool
  default     = false
}

################################################################################
# ECR
################################################################################
variable "ecr_litellm_repository" {
  description = "Name of the ECR repository containing the LiteLLM image."
  type        = string
  default     = "litellm"
}

variable "ecr_middleware_repository" {
  description = "Name of the ECR repository containing the Middleware image."
  type        = string
  default     = "middleware"
}

variable "litellm_version" {
  description = "Image tag to deploy for LiteLLM."
  type        = string
  default     = "latest"
}

################################################################################
# RDS
################################################################################
variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "Allocated storage (GiB) for the RDS instance."
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS."
  type        = bool
  default     = false
}

variable "rds_performance_insights_enabled" {
  description = "Enable Performance Insights for RDS."
  type        = bool
  default     = false
}

variable "rds_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 = disabled)."
  type        = number
  default     = 0
}

################################################################################
# Redis
################################################################################
variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache nodes (primary + replicas)."
  type        = number
  default     = 2
}

################################################################################
# ECS service sizing
################################################################################
variable "vcpus" {
  description = "Number of vCPUs for the ECS task (cpu = vcpus * 1024)."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of ECS tasks."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks (auto-scaling floor)."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks (auto-scaling ceiling)."
  type        = number
  default     = 4
}

variable "cpu_target_utilization_percent" {
  description = "Target CPU utilization for auto-scaling."
  type        = number
  default     = 70
}

variable "memory_target_utilization_percent" {
  description = "Target memory utilization for auto-scaling."
  type        = number
  default     = 80
}

variable "architecture" {
  description = "CPU architecture for the ECS task: x86 or arm."
  type        = string
  default     = "x86"

  validation {
    condition     = contains(["x86", "arm"], var.architecture)
    error_message = "architecture must be 'x86' or 'arm'."
  }
}

################################################################################
# Networking / ALB
################################################################################
variable "public_load_balancer" {
  description = "Whether the ALB is internet-facing (true) or internal (false)."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ARN of an ACM certificate for the HTTPS listener. Leave empty to use a self-signed cert."
  type        = string
  default     = ""
}

################################################################################
# CloudFront
################################################################################
variable "use_cloudfront" {
  description = "Whether to provision a CloudFront distribution in front of the ALB."
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

################################################################################
# LiteLLM runtime
################################################################################
variable "disable_swagger_page" {
  description = "Disable the LiteLLM Swagger UI page."
  type        = bool
  default     = false
}

variable "disable_admin_ui" {
  description = "Disable the LiteLLM admin UI."
  type        = bool
  default     = false
}

variable "okta_issuer" {
  description = "Okta issuer URL (for middleware JWT validation)."
  type        = string
  default     = ""
}

variable "okta_audience" {
  description = "Okta audience (for middleware JWT validation)."
  type        = string
  default     = ""
}

variable "langsmith_project" {
  description = "Langsmith project name."
  type        = string
  default     = ""
}

variable "langsmith_default_run_name" {
  description = "Langsmith default run name."
  type        = string
  default     = ""
}

variable "langfuse_public_key" {
  description = "Langfuse public key."
  type        = string
  default     = ""
}

variable "langfuse_host" {
  description = "Langfuse host URL."
  type        = string
  default     = ""
}

################################################################################
# LLM API keys (all sensitive, all default to empty string)
################################################################################
variable "openai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "azure_openai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "azure_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "anthropic_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "groq_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cohere_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "co_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "hf_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "huggingface_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "databricks_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "codestral_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "mistral_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "azure_ai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "nvidia_nim_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "xai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "perplexityai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "github_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "deepseek_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ai21_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "langsmith_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "langfuse_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}
