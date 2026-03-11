###############################################################################
# modules/s3-private
#
# Generic hardened private S3 bucket.
# - AES-256 server-side encryption
# - Full public access block
# - Enforce-SSL bucket policy (+ optional ALB access-log delivery policy)
# - Optional versioning
# - Optional lifecycle expiration rule
#
# Reusable for: ALB access logs, config buckets, artifact stores, etc.
###############################################################################

locals {
  use_prefix = var.bucket_name == ""
}

resource "aws_s3_bucket" "this" {
  bucket        = local.use_prefix ? null : var.bucket_name
  bucket_prefix = local.use_prefix ? var.bucket_prefix : null
  force_destroy = var.force_destroy

  tags = {
    Name = var.name
  }
}

# ── Encryption ──────────────────────────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Block all public access ──────────────────────────────────────────────────
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Versioning ───────────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "this" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Lifecycle rule ───────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.lifecycle_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = var.lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_expiration_days
    }
  }
}

# ── Bucket policy ────────────────────────────────────────────────────────────
# Always deny non-SSL access. Optionally allow ALB log delivery.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "EnforceSSLOnly"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.this.arn,
            "${aws_s3_bucket.this.arn}/*"
          ]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        }
      ],
      var.enable_alb_log_delivery ? [
        {
          # Required by ALB to deliver access logs
          # https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
          Sid    = "AllowALBLogDelivery"
          Effect = "Allow"
          Principal = {
            Service = "delivery.logs.amazonaws.com"
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.this.arn}/*"
          Condition = {
            StringEquals = {
              "s3:x-amz-acl"      = "bucket-owner-full-control"
              "aws:SourceAccount" = var.aws_account_id
            }
          }
        },
        {
          Sid    = "AllowALBLogDeliveryACLCheck"
          Effect = "Allow"
          Principal = {
            Service = "delivery.logs.amazonaws.com"
          }
          Action   = "s3:GetBucketAcl"
          Resource = aws_s3_bucket.this.arn
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.aws_account_id
            }
          }
        }
      ] : []
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
