output "ssh_private_key_pem_path" {
  description = "Local path to the generated private key (only when generate_ssh_key_pair is true)."
  value       = length(aws_key_pair.generated) > 0 ? abspath(local_sensitive_file.ssh_private_pem[0].filename) : null
  sensitive   = true
}

output "ssh_key_pair_name" {
  description = "EC2 key pair name attached to both instances."
  value       = length(aws_key_pair.generated) > 0 ? aws_key_pair.generated[0].key_name : (var.ec2_key_name != "" ? var.ec2_key_name : null)
}

output "cloudwatch_log_group_name" {
  description = "Log group for CloudWatch Agent (system + cloud-init files)."
  value       = aws_cloudwatch_log_group.ec2.name
}

output "cloudwatch_log_group_arn" {
  value = aws_cloudwatch_log_group.ec2.arn
}

output "config_bucket_id" {
  description = "S3 bucket for LiteLLM config and artifacts."
  value       = module.config_bucket.bucket_id
}

output "litellm_manual_bootstrap_hint" {
  description = "If /opt/litellm is missing, run scripts/bootstrap-litellm-manual.sh on the LiteLLM instance with LITELLM_CONFIG_BUCKET set to config_bucket_id, or run terraform apply to replace the instance so user_data runs again."
  value       = "export LITELLM_CONFIG_BUCKET=${module.config_bucket.bucket_id} AWS_REGION=${var.aws_region}"
}

output "github_deploy_public_key_openssh" {
  description = "Add this key in GitHub: repository Settings → Deploy keys → Add deploy key (read-only). Apply before the instance first boots, or replace the instance after adding the key."
  value       = var.use_git_clone ? tls_private_key.github_deploy[0].public_key_openssh : null
}

output "litellm_instance_id" {
  description = "LiteLLM + Postgres EC2 instance ID."
  value       = module.litellm_ec2.id
}

output "nginx_instance_id" {
  description = "Nginx edge EC2 instance ID."
  value       = module.nginx_ec2.id
}

# Backward-compatible name: was a single instance; now the browser-facing host.
output "ec2_instance_id" {
  description = "Deprecated alias: use nginx_instance_id for the edge host."
  value       = module.nginx_ec2.id
}

output "litellm_private_ip" {
  description = "Private IPv4 of the LiteLLM host (upstream for Nginx)."
  value       = module.litellm_ec2.private_ip
}

output "ec2_private_ip" {
  description = "Same as litellm_private_ip (LiteLLM host)."
  value       = module.litellm_ec2.private_ip
}

output "nginx_public_ip" {
  description = "Public IPv4 of the Nginx host — use http://<ip>/ in the browser."
  value       = module.nginx_ec2.public_ip
}

output "ec2_public_ip" {
  description = "Public IPv4 of the Nginx edge (same as nginx_public_ip)."
  value       = module.nginx_ec2.public_ip
}

output "edge_security_group_id" {
  value = aws_security_group.edge.id
}

output "litellm_security_group_id" {
  value = aws_security_group.litellm.id
}
