###############################################################################
# modules/rds-postgres
###############################################################################

# ── Random master password ───────────────────────────────────────────────────
resource "random_password" "master" {
  length  = 16
  special = false
}

# ── Secrets Manager: master credential ──────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credential" {
  name_prefix             = "${var.name}-db-credential-"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name}-db-credential"
  }
}

resource "aws_secretsmanager_secret_version" "db_credential" {
  secret_id = aws_secretsmanager_secret.db_credential.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.master.result
  })
}

# ── Security group ───────────────────────────────────────────────────────────
resource "aws_security_group" "this" {
  name        = "${var.name}-rds-sg"
  description = "Security group for RDS instance ${var.name}"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}

resource "aws_security_group_rule" "ingress" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = each.value
  description              = "Allow Postgres from ${each.value}"
}

# ── DB subnet group ──────────────────────────────────────────────────────────
locals {
  db_subnet_group_name = "${var.name}-db-subnet-group-${substr(replace(var.vpc_id, "vpc-", ""), 0, 8)}"
}

resource "aws_db_subnet_group" "this" {
  name       = local.db_subnet_group_name
  subnet_ids = var.subnet_ids

  tags = {
    Name = local.db_subnet_group_name
  }
}

# ── Parameter group ──────────────────────────────────────────────────────────
resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-postgres${replace(var.engine_version, ".", "-")}"
  family = "postgres${split(".", var.engine_version)[0]}"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1"
  }

  tags = {
    Name = "${var.name}-pg"
  }
}

# ── Enhanced Monitoring IAM role (optional) ──────────────────────────────────
data "aws_iam_policy_document" "rds_monitoring_assume" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${var.name}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume[0].json

  tags = {
    Name = "${var.name}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── RDS instance ─────────────────────────────────────────────────────────────
resource "aws_db_instance" "this" {
  identifier        = "${var.name}-db"
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  
  # FIX: Change to gp2 for Free Tier compatibility. 
  # AWS Free Tier is specifically tied to gp2 for RDS.
  storage_type      = "gp2" 
  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name              = var.db_name
  db_subnet_group_name = aws_db_subnet_group.this.name
  parameter_group_name = aws_db_parameter_group.this.name

  vpc_security_group_ids = [aws_security_group.this.id]
  
  # Use variables directly to avoid chicken-and-egg issues with jsondecode
  username = var.db_username
  password = random_password.master.result

  multi_az                        = var.multi_az
  performance_insights_enabled    = var.performance_insights_enabled
  enabled_cloudwatch_logs_exports = ["postgresql"]
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  apply_immediately               = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  tags = {
    Name = "${var.name}-db"
  }

  # FIX: Stronger dependencies to prevent "Subnet in use" during destroy
  depends_on = [
    aws_secretsmanager_secret_version.db_credential,
    aws_db_subnet_group.this,
    aws_security_group.this
  ]
}