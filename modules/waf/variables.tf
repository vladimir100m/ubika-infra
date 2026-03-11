variable "name" {
  description = "Name prefix for the WAF web ACL and CloudWatch metric names."
  type        = string
}

variable "scope" {
  description = "Scope of the WAF web ACL. Use REGIONAL for ALB/API GW, CLOUDFRONT for CloudFront (must be us-east-1)."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be either REGIONAL or CLOUDFRONT."
  }
}

variable "enable_known_bad_inputs_rule" {
  description = "Whether to enable the AWS Managed Known Bad Inputs rule group."
  type        = bool
  default     = true
}
