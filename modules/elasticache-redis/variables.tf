variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the Redis cluster and security group will be created."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ElastiCache subnet group (must span at least 2 AZs)."
  type        = list(string)
}

variable "node_type" {
  description = "ElastiCache node type (e.g. cache.t3.micro, cache.r6g.large)."
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Number of cache nodes (1 = no replica, 2+ = primary + replicas)."
  type        = number
  default     = 2
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to Redis on port 6379."
  type        = list(string)
  default     = []
}
