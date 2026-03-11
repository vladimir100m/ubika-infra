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

variable "container_image" {
  description = "Full ECR image URI including tag (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/my-app:latest)."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory (MiB) for the task."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 1
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS Task Execution Role (pulls ECR images, writes CloudWatch logs)."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS Task Role (permissions for the running container, e.g. Bedrock, S3)."
  type        = string
}
