output "log_bucket_name" {
  description = "Name of the ALB access log S3 bucket."
  value       = module.alb_log_bucket.bucket_name
}

output "log_bucket_arn" {
  description = "ARN of the ALB access log S3 bucket."
  value       = module.alb_log_bucket.bucket_arn
}
