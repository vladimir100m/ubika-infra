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
