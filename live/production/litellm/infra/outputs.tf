output "service_url" {
  description = "The public URL of the LiteLLM service."
  value = var.use_cloudfront ? (
    "https://${module.cdn[0].domain_name}"
    ) : (
    "https://${module.alb.alb_dns_name}"
  )
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = module.alb.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (empty when use_cloudfront = false)."
  value       = var.use_cloudfront ? module.cdn[0].domain_name : ""
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.cluster.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = module.service.service_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)."
  value       = module.rds.endpoint
}

output "redis_endpoint" {
  description = "Redis primary endpoint."
  value       = module.redis.primary_endpoint
}

output "config_bucket_name" {
  description = "Name of the S3 config bucket."
  value       = module.config_bucket.bucket_name
}

output "task_execution_role_arn" {
  description = "ARN of the ECS Task Execution Role."
  value       = module.iam.execution_role_arn
}

output "task_role_arn" {
  description = "ARN of the ECS Task Role."
  value       = module.iam.task_role_arn
}
