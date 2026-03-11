output "primary_endpoint" {
  description = "Primary endpoint address of the Redis replication group."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Port the Redis cluster is listening on."
  value       = 6379
}

output "auth_token" {
  description = "The Redis AUTH token (sensitive)."
  value       = random_password.auth_token.result
  sensitive   = true
}

output "security_group_id" {
  description = "ID of the Redis security group."
  value       = aws_security_group.this.id
}

output "replication_group_id" {
  description = "ID of the ElastiCache replication group."
  value       = aws_elasticache_replication_group.this.id
}
