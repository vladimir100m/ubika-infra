variable "name" {
  description = "Name of the ECS service."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster to deploy the service into."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ECS tasks."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to the ECS tasks."
  type        = list(string)
  default     = []
}

variable "container_definitions" {
  description = "JSON-encoded list of container definitions for the task."
  type        = string
}

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)."
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Memory (MiB) for the task."
  type        = number
  default     = 2048
}

variable "cpu_architecture" {
  description = "CPU architecture for the task: X86_64 or ARM64."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 1
}

variable "min_count" {
  description = "Minimum number of running tasks for auto-scaling."
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum number of running tasks for auto-scaling."
  type        = number
  default     = 4
}

variable "cpu_target_utilization_percent" {
  description = "Target CPU utilization (%) for auto-scaling."
  type        = number
  default     = 70
}

variable "memory_target_utilization_percent" {
  description = "Target memory utilization (%) for auto-scaling."
  type        = number
  default     = 80
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to wait before starting health checks on a new task."
  type        = number
  default     = 300
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS Task Execution Role (pulls ECR images, writes CloudWatch logs, reads Secrets Manager)."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS Task Role (permissions for the running container, e.g. Bedrock, S3)."
  type        = string
}

variable "load_balancers" {
  description = "List of load balancer target group bindings for the service."
  type = list(object({
    target_group_arn = string
    container_name   = string
    container_port   = number
  }))
  default = []
}
