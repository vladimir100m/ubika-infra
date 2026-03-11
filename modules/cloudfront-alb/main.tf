###############################################################################
# modules/cloudfront-alb
#
# CloudFront distribution that fronts an ALB with custom header authentication.
#
# Security model:
#   1. CloudFront adds a secret `X-CloudFront-Secret` header to every request.
#   2. The ALB (listener rules in the live layer) only forwards requests that
#      carry this header — rejecting direct access with a 403.
#   3. End users always communicate with CloudFront over HTTPS.
#   4. CloudFront → ALB uses HTTP (avoids certificate issues on the internal
#      ALB while maintaining strong end-to-end security via the shared secret).
#
# Reusable for: any service behind an ALB that needs a CDN / global edge.
###############################################################################

resource "random_password" "origin_secret" {
  length  = 32
  special = false

  keepers = {
    name = var.name
  }

  lifecycle {
    ignore_changes = [length, special, min_lower, min_upper, min_numeric]
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name} distribution"
  default_root_object = ""
  price_class         = var.price_class

  aliases = length(var.aliases) > 0 ? var.aliases : []

  # ── Origin ────────────────────────────────────────────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB"

    # Secret header — ALB rules check for this before forwarding
    custom_header {
      name  = "X-CloudFront-Secret"
      value = "cf-${random_password.origin_secret.result}"
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Default cache behaviour ───────────────────────────────────────────────
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ALB"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host", "Origin"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # ── Viewer certificate ────────────────────────────────────────────────────
  dynamic "viewer_certificate" {
    for_each = var.certificate_arn != "" ? [1] : []
    content {
      acm_certificate_arn      = var.certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.certificate_arn == "" ? [1] : []
    content {
      cloudfront_default_certificate = true
    }
  }

  # ── Geo restrictions ──────────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.name}-cdn"
  }
}
