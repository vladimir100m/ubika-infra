variable "aws_region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "mvp"
}

variable "name" {
  description = "Prefix on VPC and related resources."
  type        = string
  default     = "mvp"
}

variable "vpc_id" {
  description = "If set, use this VPC instead of creating a new one."
  type        = string
  default     = ""
}

variable "create_vpc_endpoints_in_existing_vpc" {
  description = "If using an existing VPC, set true to create endpoints in it."
  type        = bool
  default     = false
}

variable "disable_outbound_network_access" {
  description = "Whether to disable outbound network access (forces no NAT)."
  type        = bool
  default     = false
}
