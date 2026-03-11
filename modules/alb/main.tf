###############################################################################
# modules/alb
###############################################################################

# ── Security group ───────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for ALB ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.internal ? var.private_subnet_cidr_blocks : ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.internal ? var.private_subnet_cidr_blocks : ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

# ── Self-signed certificate ──────────────────────────────────────────────────
resource "tls_private_key" "self_signed" {
  count     = var.certificate_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count           = var.certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "${var.name}.internal"
    organization = var.name
  }

  validity_period_hours = 8760 

  allowed_uses = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "self_signed" {
  count            = var.certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# ── ALB ──────────────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = var.idle_timeout

  drop_invalid_header_fields = true

  # FIX: Explicitly depend on the SG to ensure the LB's ENIs are 
  # fully deleted before the SG/Subnet destruction cycle begins.
  depends_on = [aws_security_group.alb]

  dynamic "access_logs" {
    for_each = var.log_bucket_name != "" ? [1] : []
    content {
      bucket  = var.log_bucket_name
      prefix  = var.log_bucket_prefix
      enabled = true
    }
  }

  tags = {
    Name = "${var.name}-alb"
  }
}

# ── Target groups ────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "${var.name}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # SENIOR TIP: Reduce delay for faster container cycling in dev/staging
  deregistration_delay = 30 

  health_check {
    path                = each.value.health_check_path
    port                = each.value.health_check_port
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }

  tags = {
    Name = "${var.name}-tg-${each.key}"
  }
}

# ── Listeners ────────────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = var.default_target_group_key != "" ? aws_lb_target_group.this[var.default_target_group_key].arn : values(aws_lb_target_group.this)[0].arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate.self_signed[0].arn

  default_action {
    type             = "forward"
    target_group_arn = var.default_target_group_key != "" ? aws_lb_target_group.this[var.default_target_group_key].arn : values(aws_lb_target_group.this)[0].arn
  }
}

# ── WAF association ──────────────────────────────────────────────────────────
resource "aws_wafv2_web_acl_association" "this" {
  count        = var.enable_waf_association ? 1 : 0
  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_arn
}