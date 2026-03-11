output "endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the RDS instance (without port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port of the RDS instance."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "ID of the RDS security group."
  value       = aws_security_group.this.id
}

output "credential_secret_arn" {
  description = "ARN of the Secrets Manager secret containing {username, password}."
  value       = aws_secretsmanager_secret.db_credential.arn
}

output "username" {
  description = "Master username."
  value       = var.db_username
}

output "password" {
  description = "Master password (sensitive)."
  value       = random_password.master.result
  sensitive   = true
}
