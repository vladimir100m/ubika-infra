variable "name" {
  type        = string
  description = "IAM role name (and default instance profile name)."
}

variable "instance_profile_name" {
  type        = string
  description = "Optional override for aws_iam_instance_profile name."
  default     = ""
}
