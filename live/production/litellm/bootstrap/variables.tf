variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (e.g. production, staging)."
  type        = string
  default     = "production"
}

variable "name" {
  description = "Name prefix for resources."
  type        = string
  default     = "genai-gateway"
}

variable "aws_account_id" {
  description = "AWS account ID — used to scope the ALB log delivery bucket policy."
  type        = string
  default     = "703544859494"
}

variable "log_retention_days" {
  description = "Number of days to retain ALB access logs in S3. Set to 0 to disable lifecycle rule."
  type        = number
  default     = 90
}
