variable "name" {
  description = "Name prefix used for bucket naming and tags."
  type        = string
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (mutually exclusive with bucket_name)."
  type        = string
  default     = ""
}

variable "bucket_name" {
  description = "Explicit bucket name. Leave empty to use bucket_prefix for a unique generated name."
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Whether to allow Terraform to destroy the bucket even if it contains objects."
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Whether to enable versioning on the bucket."
  type        = bool
  default     = false
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which objects expire. Set to 0 to disable lifecycle rule."
  type        = number
  default     = 0
}

variable "enable_alb_log_delivery" {
  description = "Whether to add an S3 bucket policy statement allowing the ALB service to write access logs."
  type        = bool
  default     = false
}

variable "aws_account_id" {
  description = "AWS account ID — required when enable_alb_log_delivery is true."
  type        = string
  default     = ""
}
