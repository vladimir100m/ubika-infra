output "distribution_id" {
  description = "ID of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.id
}

output "domain_name" {
  description = "Domain name of the CloudFront distribution (e.g. d1234.cloudfront.net)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "origin_secret" {
  description = "The X-CloudFront-Secret header value sent to the origin ALB (sensitive)."
  value       = "cf-${random_password.origin_secret.result}"
  sensitive   = true
}
