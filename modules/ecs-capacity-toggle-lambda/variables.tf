variable "name" {
  description = "Prefix for Lambda and IAM resources."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name (not ARN)."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name."
  type        = string
}

variable "max_task_count" {
  description = "Application Auto Scaling maximum task count (must match ECS service max_capacity in Terraform)."
  type        = number
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 128
}
