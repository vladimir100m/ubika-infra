output "ssh_private_key_pem_path" {
  description = "Local path to the generated private key (only when generate_ssh_key_pair is true)."
  value       = length(aws_key_pair.generated) > 0 ? abspath(local_sensitive_file.ssh_private_pem[0].filename) : null
  sensitive   = true
}

output "ssh_key_pair_name" {
  description = "EC2 key pair name attached to the instance."
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
  description = "If /opt/litellm is missing, run scripts/bootstrap-litellm-manual.sh on the instance with LITELLM_CONFIG_BUCKET set to config_bucket_id, or run terraform apply to replace the instance so user_data runs again."
  value       = "export LITELLM_CONFIG_BUCKET=${module.config_bucket.bucket_id} AWS_REGION=${var.aws_region}"
}

output "github_deploy_public_key_openssh" {
  description = "Add this key in GitHub: repository Settings → Deploy keys → Add deploy key (read-only). Apply before the instance first boots, or replace the instance after adding the key."
  value       = var.use_git_clone ? tls_private_key.github_deploy[0].public_key_openssh : null
}

output "ec2_instance_id" {
  value = aws_instance.this.id
}

output "ec2_private_ip" {
  value = aws_instance.this.private_ip
}

output "ec2_public_ip" {
  description = "Public IPv4 for outbound (e.g. Docker pulls). Restrict edge ingress in SGs if using tunnel-only access patterns."
  value       = aws_instance.this.public_ip
}

output "edge_security_group_id" {
  value = aws_security_group.edge.id
}

output "litellm_security_group_id" {
  value = aws_security_group.litellm.id
}
