variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the RDS instance and security group will be created."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (must span at least 2 AZs)."
  type        = list(string)
}

variable "db_name" {
  description = "Name of the initial database to create."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username for the database."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "15"
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t3.medium, db.r6g.large)."
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Whether to enable Multi-AZ for high availability."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 = disabled). Valid values: 0, 1, 5, 10, 15, 30, 60."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot before deletion."
  type        = bool
  default     = true
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to the DB on port 5432."
  type        = list(string)
  default     = []
}
