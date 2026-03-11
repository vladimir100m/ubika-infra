###############################################################################
# live/production/litellm/bootstrap
#
# Pre-requisite layer for the LiteLLM infra stack.
# Must be deployed BEFORE live/production/litellm/infra/ because the ALB
# access_logs configuration is applied at creation time and cannot be set
# on a bucket that doesn't exist yet.
#
# Resources:
#   - S3 bucket for ALB access logs (modules/s3-private)
#
# State: production/litellm/bootstrap/terraform.tfstate
###############################################################################

module "alb_log_bucket" {
  source = "../../../../modules/s3-private"

  name          = "${var.name}-litellm-alb-logs-${local.aws_account_id}"
  bucket_prefix = "${var.name}-litellm-alb-logs-"
  force_destroy = false

  # Retain logs for 90 days by default
  lifecycle_expiration_days = var.log_retention_days

  # Allow the ELB service principal to write access logs
  enable_alb_log_delivery = true
  aws_account_id          = var.aws_account_id
}
