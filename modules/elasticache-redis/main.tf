###############################################################################
# modules/elasticache-redis
#
# Generic Redis 7 ElastiCache replication group.
# - Random auth token (transit encryption required)
# - At-rest encryption
# - Multi-AZ with automatic failover
# - Security group with configurable ingress
#
# Reusable for: any service that needs a managed Redis cache/session store.
###############################################################################

data "aws_region" "current" {}

# ── Random auth token ────────────────────────────────────────────────────────
resource "random_password" "auth_token" {
  length  = 32
  special = false
}

# ── Security group ───────────────────────────────────────────────────────────
resource "aws_security_group" "this" {
  name        = "${var.name}-redis-sg"
  description = "Security group for Redis cluster ${var.name}"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-redis-sg"
  }
}

resource "aws_security_group_rule" "ingress" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = each.value
  description              = "Allow Redis from ${each.value}"
}

# ── Subnet group ─────────────────────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name}-redis-subnet-group"
  description = "Subnet group for Redis cluster ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name}-redis-subnet-group"
  }
}

# ── Parameter group ──────────────────────────────────────────────────────────
resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.name}-redis-pg"
  family      = "redis${split(".", var.engine_version)[0]}"
  description = "Parameter group for Redis cluster ${var.name}"

  parameter {
    name  = "timeout"
    value = "0"
  }

  tags = {
    Name = "${var.name}-redis-pg"
  }
}

# ── Replication group ────────────────────────────────────────────────────────
locals {
  effective_automatic_failover = coalesce(var.automatic_failover_enabled, var.num_cache_clusters > 1)
  effective_multi_az           = coalesce(var.multi_az_enabled, var.num_cache_clusters > 1)
  replication_group_id         = "${var.name}-redis"
}

# The AWS Terraform provider can invoke DecreaseReplicaCount before AutomaticFailoverEnabled is
# applied, which ElastiCache rejects. When scaling to one node, disable failover via CLI first.
resource "null_resource" "pre_modify_disable_failover" {
  triggers = {
    desired_nodes = tostring(var.num_cache_clusters)
    enabled       = tostring(var.pre_modify_disable_failover_via_cli)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = templatefile("${path.module}/pre_modify_failover.sh.tpl", {
      rg_id   = local.replication_group_id
      region  = data.aws_region.current.name
      desired = tostring(var.num_cache_clusters)
      enabled = var.pre_modify_disable_failover_via_cli ? "true" : "false"
    })
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.replication_group_id
  description          = "Redis replication group for ${var.name}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.effective_automatic_failover
  multi_az_enabled           = local.effective_multi_az

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]

  port = 6379

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  auth_token                 = random_password.auth_token.result
  auth_token_update_strategy = "SET"

  apply_immediately = true

  tags = {
    Name = "${var.name}-redis"
  }

  depends_on = [
    aws_elasticache_subnet_group.this,
    aws_elasticache_parameter_group.this,
    null_resource.pre_modify_disable_failover,
  ]
}
