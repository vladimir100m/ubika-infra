###############################################################################
# modules/waf
#
# Generic WAFv2 Web ACL with AWS Managed Rule Groups.
# Scope can be REGIONAL (ALB / API Gateway) or CLOUDFRONT.
#
# Rules:
#   1. AWSManagedRulesCommonRuleSet       (priority 1)
#      - NoUserAgent_HEADER  → count (allow LLM clients that omit User-Agent)
#      - SizeRestrictions_BODY → count (LLM payloads can be large)
#   2. AWSManagedRulesKnownBadInputsRuleSet (priority 2, optional)
#
# Reusable for: any ALB, API Gateway, or CloudFront distribution.
###############################################################################

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-waf"
  description = "WAF web ACL for ${var.name}"
  scope       = var.scope

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = replace("${var.name}WebAcl", "-", "")
    sampled_requests_enabled   = true
  }

  # ── AWS Managed Common Rule Set ─────────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # LLM API clients often omit User-Agent — count instead of block.
        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use { count {} }
        }

        # LLM request/response bodies can be very large — count instead of block.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use { count {} }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = replace("${var.name}CommonRuleSet", "-", "")
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed Known Bad Inputs Rule Set ───────────────────────────────────
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs_rule ? [1] : []
    content {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 2

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}KnownBadInputs", "-", "")
        sampled_requests_enabled   = true
      }
    }
  }
}
