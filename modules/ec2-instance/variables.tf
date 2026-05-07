variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "iam_instance_profile" {
  type = string
}

variable "associate_public_ip_address" {
  type    = bool
  default = true
}

variable "key_name" {
  type    = string
  default = null
}

variable "user_data" {
  type    = string
  default = null
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "root_volume_type" {
  type    = string
  default = "gp3"
}

variable "metadata_http_tokens" {
  type    = string
  default = "required"
}

variable "instance_name" {
  type        = string
  description = "Default Name tag."
}

variable "tags" {
  type    = map(string)
  default = {}
}
