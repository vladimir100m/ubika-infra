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

variable "automatic_failover_enabled" {
  description = "If null (default), failover is on when num_cache_clusters > 1. Set false and keep num_cache_clusters at the current count for one apply before lowering num_cache_clusters to 1 (AWS requires failover off before removing the last replica)."
  type        = bool
  default     = null
}

variable "multi_az_enabled" {
  description = "If null (default), Multi-AZ follows num_cache_clusters > 1. Override together with automatic_failover_enabled when migrating down to a single node."
  type        = bool
  default     = null
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to Redis on port 6379."
  type        = list(string)
  default     = []
}

variable "pre_modify_disable_failover_via_cli" {
  description = "Before Terraform shrinks a multi-node group to one node, run AWS CLI to disable automatic failover (Terraform provider can call DecreaseReplicaCount before failover is off). Requires aws CLI in PATH. Set false in environments where local-exec cannot run."
  type        = bool
  default     = true
}
