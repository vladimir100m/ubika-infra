output "bucket_id" {
  description = "The name (ID) of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "The name of the bucket (same as bucket_id)."
  value       = aws_s3_bucket.this.bucket
}
