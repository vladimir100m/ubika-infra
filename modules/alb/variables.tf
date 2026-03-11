variable "name" {
  description = "Name prefix for all ALB resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the ALB will be deployed."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ALB (use public subnets for internet-facing, private for internal)."
  type        = list(string)
}

variable "internal" {
  description = "Whether the ALB is internal (true) or internet-facing (false)."
  type        = bool
  default     = false
}

variable "private_subnet_cidr_blocks" {
  description = "CIDR blocks of private subnets — used for internal ALB ingress rules."
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS. Leave empty to use a self-signed certificate."
  type        = string
  default     = ""
}

variable "waf_arn" {
  description = "ARN of a WAFv2 Web ACL to associate with the ALB. Leave empty to skip association."
  type        = string
  default     = ""
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket to which ALB access logs will be delivered. Leave empty to disable."
  type        = string
  default     = ""
}

variable "log_bucket_prefix" {
  description = "Prefix for ALB access log objects in the S3 bucket."
  type        = string
  default     = "alb-access-logs"
}

variable "idle_timeout" {
  description = "Connection idle timeout in seconds."
  type        = number
  default     = 60
}

# ---------------------------------------------------------------------------
# Target groups
# Each entry describes one target group. The module creates all of them.
# The live layer then creates listener rules that reference these TGs by key.
#
# Format:
#   target_groups = {
#     "litellm" = { port = 4000, health_check_path = "/health/liveliness" }
#     "middleware" = { port = 3000, health_check_path = "/bedrock/health/liveliness" }
#   }
# ---------------------------------------------------------------------------
variable "target_groups" {
  description = "Map of target group definitions. Key becomes part of the TG name."
  type = map(object({
    port              = number
    health_check_path = string
    health_check_port = optional(string, "traffic-port")
  }))
  default = {}
}

variable "default_target_group_key" {
  description = "Key from var.target_groups to use as the default action for both listeners."
  type        = string
  default     = ""
}
