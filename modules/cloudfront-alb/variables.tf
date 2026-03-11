variable "name" {
  description = "Name prefix used for resource tags and comments."
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB to use as the CloudFront origin."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US/Europe only (cheapest)."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN for a custom domain. Must be in us-east-1. Leave empty to use CloudFront default cert."
  type        = string
  default     = ""
}

variable "aliases" {
  description = "Custom domain aliases for the CloudFront distribution (requires certificate_arn)."
  type        = list(string)
  default     = []
}
