variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "mvp"
}

variable "name" {
  type        = string
  description = "Prefix for resources."
  default     = "mvp-litellm"
}

variable "terraform_state_bucket" {
  type        = string
  description = "S3 bucket holding Terraform state."
  default     = "terraform-mvp-591667019512"
}

variable "networking_state_key" {
  type        = string
  description = "State key for live/mvp/networking."
  default     = "mvp/networking/terraform.tfstate"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (x86_64 AL2023 AMI)."
  default     = "c7i-flex.large"
}

variable "edge_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach Nginx/Agent ports (e.g. Vercel has no fixed hobby IPs; use app-layer auth if using 0.0.0.0/0)."
  default     = ["0.0.0.0/0"]
}

variable "edge_ingress_ports" {
  type        = list(number)
  description = "Ports exposed for external HTTPS/HTTP (Nginx, Agent)."
  default     = [80, 443]
}

variable "litellm_port" {
  type        = number
  description = "LiteLLM listen port (not exposed to edge_ingress_cidrs; VPC + edge SG only)."
  default     = 4000
}

variable "volume_size_gb" {
  type        = number
  description = "Root EBS volume size (gp3)."
  default     = 30
}

variable "user_data" {
  type        = string
  description = "Optional extra shell appended after Docker install."
  default     = ""
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "Retention for EC2 system logs in CloudWatch Logs."
  default     = 30
}

variable "ssh_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed for SSH (TCP 22) on the edge security group. Empty = no SSH from the internet (use SSM Session Manager instead)."
  default     = []
}

variable "generate_ssh_key_pair" {
  type        = bool
  description = "If true, generate an RSA key with the tls provider, upload to AWS as a key pair, and write the private .pem in live/mvp/litellm/ (parent of infra/; gitignored)."
  default     = true
}

variable "ec2_key_name" {
  type        = string
  description = "Use an existing EC2 key pair name in this region (only when generate_ssh_key_pair is false)."
  default     = ""

  validation {
    condition     = !var.generate_ssh_key_pair || var.ec2_key_name == ""
    error_message = "When generate_ssh_key_pair is true, leave ec2_key_name empty."
  }
}

variable "use_git_clone" {
  type        = bool
  description = "If true, generate a GitHub deploy key in SSM and clone git_repo_ssh_url on boot; compose runs from git_compose_relative_path under git_clone_path. If false, copy compose files from S3 bootstrap/ only."
  default     = true
}

variable "git_repo_ssh_url" {
  type        = string
  description = "SSH URL for git clone (deploy key must be added to that repo on GitHub)."
  default     = "git@github.com:vladimir100m/ubika-infra.git"
}

variable "git_branch" {
  type        = string
  description = "Branch to clone/checkout."
  default     = "main"
}

variable "git_clone_path" {
  type        = string
  description = "Absolute path on the instance where the repo is cloned."
  default     = "/opt/ubika-infra"
}

variable "git_compose_relative_path" {
  type        = string
  description = "Directory under the repo root containing docker-compose.yaml for LiteLLM."
  default     = "live/mvp/litellm"
}
