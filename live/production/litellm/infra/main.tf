###############################################################################
# live/production/litellm/infra
# Main LiteLLM infrastructure layer.
# Reads networking state from live/production/networking/ and wires together:
#
#   Generic modules (reusable across the infra):
#     modules/waf/                  → WAF web ACL
#     modules/rds-postgres/         → Postgres 15 database
#     modules/elasticache-redis/    → Redis 7 cache
#     modules/s3-private/           → Config bucket
#     modules/iam-roles/            → Task Execution + Task roles
#     modules/ecs-cluster/          → Fargate cluster
#     modules/alb/                  → Application Load Balancer
#     modules/cloudfront-alb/       → CloudFront CDN (optional)
#
#   LiteLLM-specific resources (inline — not worth a module):
#     aws_secretsmanager_secret     → LiteLLM master/salt keys
#     aws_secretsmanager_secret     → LLM API keys bundle
#     aws_secretsmanager_secret     → DB connection URL
#     aws_cloudwatch_log_group      → /ecs/litellm, /ecs/middleware
#     aws_iam_policy                → Task Role inline policy (S3, Bedrock, etc.)
#     aws_ecs_task_definition       → LiteLLM + Middleware containers
#     aws_ecs_service               → Fargate service with 2 TG bindings
#     module.ecs_scale_toggle       → Lambda to set desired/min tasks to 0 or 1 (manual invoke)
#     aws_lb_listener_rule          → All LiteLLM routing rules
#     aws_s3_object                 → config.yaml upload
#     aws_security_group            → ECS task SG
#
# State: production/litellm/infra/terraform.tfstate
###############################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Exposed as a local so every resource that needs the account ID reads from
  # one place.  Dynamically resolved — no need to hard-code.
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ── Read pre-requisite state ─────────────────────────────────────────────────

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "terraform-ubika-703544859494"
    key    = "production/networking/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "bootstrap" {
  count = var.read_bootstrap_remote_state ? 1 : 0

  backend = "s3"
  config = {
    bucket = "terraform-ubika-703544859494"
    key    = "production/litellm/bootstrap/terraform.tfstate"
    region = "us-east-1"
  }
}

# ── ECR repositories (must already exist) ───────────────────────────────────

data "aws_ecr_repository" "litellm" {
  name = var.ecr_litellm_repository
}

data "aws_ecr_repository" "middleware" {
  name = var.ecr_middleware_repository
}

locals {
  # Backward-compatible remote-state key support.
  networking_vpc_id = try(
    data.terraform_remote_state.networking.outputs.vpc_id,
    data.terraform_remote_state.networking.outputs.VpcId,
  )

  log_bucket_name = var.read_bootstrap_remote_state ? try(data.terraform_remote_state.bootstrap[0].outputs.log_bucket_name, "") : ""
  log_bucket_arn  = var.read_bootstrap_remote_state ? try(data.terraform_remote_state.bootstrap[0].outputs.log_bucket_arn, "") : ""
}

# ── Generic modules ──────────────────────────────────────────────────────────

module "waf" {
  source = "../../../../modules/waf"
  name   = "${var.name}-litellm"
  scope  = "REGIONAL"
}

module "rds" {
  source = "../../../../modules/rds-postgres"

  name       = "${var.name}-litellm"
  vpc_id     = local.networking_vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids

  db_name                      = "litellm"
  db_username                  = "llmproxy"
  instance_class               = var.rds_instance_class
  allocated_storage            = var.rds_allocated_storage
  multi_az                     = var.rds_multi_az
  performance_insights_enabled = var.rds_performance_insights_enabled
  monitoring_interval          = var.rds_monitoring_interval

  # SG rules are attached in this root module after both SGs exist.
  allowed_security_group_ids = []
}

module "redis" {
  source = "../../../../modules/elasticache-redis"

  name       = "${var.name}-litellm"
  vpc_id     = local.networking_vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids

  node_type          = var.redis_node_type
  num_cache_clusters = var.redis_num_cache_clusters

  # SG rules are attached in this root module after both SGs exist.
  allowed_security_group_ids = []
}

module "config_bucket" {
  source = "../../../../modules/s3-private"

  name          = "${var.name}-litellm-config"
  bucket_name   = "${var.name}-litellm-config-${local.aws_account_id}"
  force_destroy = true
}

module "iam" {
  source = "../../../../modules/iam-roles"

  name = "${var.name}-litellm"

  # Execution role needs to read Secrets Manager at task start
  extra_secrets_arns = [
    aws_secretsmanager_secret.master_salt.arn,
    aws_secretsmanager_secret.db_url.arn,
    aws_secretsmanager_secret.llm_api_keys.arn,
    aws_secretsmanager_secret.redis_auth.arn,
  ]

  # Attachments are created in root to avoid for_each unknown issues at plan time.
  task_role_policy_arns = []
}

module "cluster" {
  source = "../../../../modules/ecs-cluster"
  name   = "${var.name}-litellm"
}

module "alb" {
  source = "../../../../modules/alb"

  name       = "${var.name}-litellm"
  vpc_id     = local.networking_vpc_id
  subnet_ids = var.public_load_balancer ? data.terraform_remote_state.networking.outputs.public_subnet_ids : data.terraform_remote_state.networking.outputs.private_subnet_ids

  internal               = !var.public_load_balancer
  certificate_arn        = var.certificate_arn
  waf_arn                = module.waf.web_acl_arn
  enable_waf_association = true
  log_bucket_name        = local.log_bucket_name
  idle_timeout           = 300 # 5 min to reduce 504s during slow/streaming requests

  target_groups = merge(
    {
      litellm = {
        port              = 4000
        health_check_path = "/health/readiness"
        health_check_path = "/health/readiness"
        health_check_port = "4000"
      }
    },
    var.enable_middleware ? {
      middleware = {
        port              = 3000
        health_check_path = "/bedrock/health/liveliness"
        health_check_port = "3000"
      }
    } : {}
  )

  default_target_group_key = "litellm"
}

module "cdn" {
  source = "../../../../modules/cloudfront-alb"
  count  = var.use_cloudfront ? 1 : 0

  name         = "${var.name}-litellm"
  alb_dns_name = module.alb.alb_dns_name
  price_class  = var.cloudfront_price_class
}

# ── LiteLLM-specific secrets ─────────────────────────────────────────────────

resource "random_password" "master" {
  length  = 21
  special = false
}

resource "random_password" "salt" {
  length  = 21
  special = false
}

resource "aws_secretsmanager_secret" "master_salt" {
  name_prefix             = "${var.name}-litellm-master-salt-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "master_salt" {
  secret_id = aws_secretsmanager_secret.master_salt.id
  secret_string = jsonencode({
    LITELLM_MASTER_KEY = "sk-${random_password.master.result}"
    LITELLM_SALT_KEY   = "sk-${random_password.salt.result}"
  })
}

resource "aws_secretsmanager_secret" "db_url" {
  name_prefix             = "${var.name}-litellm-db-url-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${module.rds.username}:${module.rds.password}@${module.rds.endpoint}/litellm"

  depends_on = [module.rds]
}

resource "aws_secretsmanager_secret" "llm_api_keys" {
  name_prefix             = "${var.name}-litellm-api-keys-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "llm_api_keys" {
  secret_id = aws_secretsmanager_secret.llm_api_keys.id
  secret_string = jsonencode({
    GEMINI_API_KEY      = var.gemini_api_key
    LANGFUSE_SECRET_KEY = var.langfuse_secret_key
    GEMINI_API_KEY      = var.gemini_api_key
    LANGFUSE_SECRET_KEY = var.langfuse_secret_key
  })
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name_prefix             = "${var.name}-litellm-redis-auth-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    REDIS_PASSWORD = module.redis.auth_token
  })

  depends_on = [module.redis]
}

# ── Config bucket: upload config.yaml ────────────────────────────────────────

resource "aws_s3_object" "config_yaml" {
  bucket = module.config_bucket.bucket_id
  key    = "config.yaml"
  source = "${path.root}/../config/config.yaml"
  etag   = filemd5("${path.root}/../config/config.yaml")
}

# ── CloudWatch log groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "litellm" {
  name              = "/ecs/${var.name}-litellm"
  retention_in_days = var.ecs_cloudwatch_log_retention_days
}

resource "aws_cloudwatch_log_group" "middleware" {
  name              = "/ecs/${var.name}-middleware"
  retention_in_days = var.ecs_cloudwatch_log_retention_days
}

# ── ECS task security group ───────────────────────────────────────────────────

resource "aws_security_group" "ecs_task" {
  name        = "${var.name}-litellm-task-sg"
  description = "Security group for LiteLLM ECS Fargate tasks"
  vpc_id      = local.networking_vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-litellm-task-sg"
  }
}

resource "aws_security_group_rule" "ecs_task_ingress_8000" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_task.id
  source_security_group_id = module.alb.alb_security_group_id
  description              = "Allow ALB to FastAPI Agent containers"
}

resource "aws_security_group_rule" "ecs_task_ingress_4000" {
  type                     = "ingress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_task.id
  source_security_group_id = module.alb.alb_security_group_id
  description              = "Allow ALB to LiteLLM container"
}

resource "aws_security_group_rule" "ecs_task_ingress_3000" {
  count                    = var.enable_middleware ? 1 : 0
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_task.id
  source_security_group_id = module.alb.alb_security_group_id
  description              = "Allow ALB to Middleware container"
}

resource "aws_security_group_rule" "redis_ingress_from_ecs" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = module.redis.security_group_id
  source_security_group_id = aws_security_group.ecs_task.id
  description              = "Allow ECS tasks to Redis"
}

resource "aws_security_group_rule" "rds_ingress_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.security_group_id
  source_security_group_id = aws_security_group.ecs_task.id
  description              = "Allow ECS tasks to RDS"
}

# This is how Repo B (CDK) knows where to deploy without hardcoding.
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/ubika/${var.environment}/vpc_id"
  type  = "String"
  value = local.networking_vpc_id
}

resource "aws_ssm_parameter" "alb_listener_arn" {
  name  = "/ubika/${var.environment}/alb_https_listener_arn"
  type  = "String"
  value = module.alb.https_listener_arn
}

resource "aws_ssm_parameter" "alb_sg_id" {
  name  = "/ubika/${var.environment}/alb_security_group_id"
  type  = "String"
  value = module.alb.alb_security_group_id
}

resource "aws_ssm_parameter" "private_subnets" {
  name  = "/ubika/${var.environment}/private_subnet_ids"
  type  = "StringList"
  value = join(",", data.terraform_remote_state.networking.outputs.private_subnet_ids)
}

resource "aws_ssm_parameter" "litellm_url" {
  name  = "/ubika/${var.environment}/litellm_url"
  type  = "String"
  value = var.use_cloudfront ? "https://${module.cdn[0].domain_name}" : "https://${module.alb.alb_dns_name}"
}

# Internal URL for agent-to-gateway communication (always ALB DNS, avoids CloudFront)
resource "aws_ssm_parameter" "litellm_internal_url" {
  name  = "/ubika/${var.environment}/litellm_internal_url"
  type  = "String"
  value = "https://${module.alb.alb_dns_name}"
}


# ── IAM: Task Role inline policy ─────────────────────────────────────────────

data "aws_iam_policy_document" "task_role" {
  statement {
    sid     = "S3ConfigBucket"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      module.config_bucket.bucket_arn,
      "${module.config_bucket.bucket_arn}/*",
    ]
  }

  dynamic "statement" {
    for_each = local.log_bucket_arn != "" ? [1] : []
    content {
      sid     = "S3LogBucket"
      actions = ["s3:*"]
      resources = [
        local.log_bucket_arn,
        "${local.log_bucket_arn}/*",
      ]
    }
  }

  statement {
    sid       = "BedrockAccess"
    actions   = ["bedrock:*"]
    resources = ["*"]
  }

  statement {
    sid       = "SageMakerInvoke"
    actions   = ["sagemaker:InvokeEndpoint"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_role" {
  name   = "${var.name}-litellm-task-policy"
  role   = module.iam.task_role_name
  policy = data.aws_iam_policy_document.task_role.json
}

# ── Container definitions (LiteLLM + Middleware) ──────────────────────────────

locals {
  cpu_architecture = var.architecture == "x86" ? "X86_64" : "ARM64"
  cpu_units        = var.vcpus * 1024
  memory_mib       = var.vcpus * 1024 * 2

  litellm_container_definition = {
    name      = "LiteLLMContainer"
    image     = "${data.aws_ecr_repository.litellm.repository_url}:${var.litellm_version}"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.litellm.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "LiteLLM"
      }
    }

    environment = [
      { name = "LITELLM_LOG", value = "DEBUG" },
      { name = "LITELLM_CONFIG_BUCKET_NAME", value = module.config_bucket.bucket_name },
      { name = "LITELLM_CONFIG_BUCKET_OBJECT_KEY", value = "config.yaml" },
      { name = "UI_USERNAME", value = "admin" },
      { name = "REDIS_HOST", value = module.redis.primary_endpoint },
      { name = "REDIS_PORT", value = tostring(module.redis.port) },
      { name = "REDIS_SSL", value = "True" },
      { name = "LANGSMITH_PROJECT", value = var.langsmith_project },
      { name = "LANGSMITH_DEFAULT_RUN_NAME", value = var.langsmith_default_run_name },
      { name = "NO_DOCS", value = var.disable_swagger_page ? "True" : "False" },
      { name = "DISABLE_ADMIN_UI", value = var.disable_admin_ui ? "True" : "False" },
      { name = "LANGFUSE_PUBLIC_KEY", value = var.langfuse_public_key },
      { name = "LANGFUSE_HOST", value = var.langfuse_host },
    ]

    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.db_url.arn },
      { name = "LITELLM_MASTER_KEY", valueFrom = "${aws_secretsmanager_secret.master_salt.arn}:LITELLM_MASTER_KEY::" },
      { name = "UI_PASSWORD", valueFrom = "${aws_secretsmanager_secret.master_salt.arn}:LITELLM_MASTER_KEY::" },
      { name = "LITELLM_SALT_KEY", valueFrom = "${aws_secretsmanager_secret.master_salt.arn}:LITELLM_SALT_KEY::" },
      { name = "REDIS_PASSWORD", valueFrom = "${aws_secretsmanager_secret.redis_auth.arn}:REDIS_PASSWORD::" },
      # { name = "OPENAI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:OPENAI_API_KEY::" },
      # { name = "AZURE_OPENAI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:AZURE_OPENAI_API_KEY::" },
      # { name = "AZURE_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:AZURE_API_KEY::" },
      # { name = "ANTHROPIC_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:ANTHROPIC_API_KEY::" },
      # { name = "GROQ_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:GROQ_API_KEY::" },
      # { name = "COHERE_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:COHERE_API_KEY::" },
      # { name = "CO_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:CO_API_KEY::" },
      # { name = "HF_TOKEN", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:HF_TOKEN::" },
      # { name = "HUGGINGFACE_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:HUGGINGFACE_API_KEY::" },
      # { name = "DATABRICKS_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:DATABRICKS_API_KEY::" },
      { name = "GEMINI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:GEMINI_API_KEY::" },
      # { name = "CODESTRAL_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:CODESTRAL_API_KEY::" },
      # { name = "MISTRAL_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:MISTRAL_API_KEY::" },
      # { name = "AZURE_AI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:AZURE_AI_API_KEY::" },
      # { name = "NVIDIA_NIM_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:NVIDIA_NIM_API_KEY::" },
      # { name = "XAI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:XAI_API_KEY::" },
      # { name = "PERPLEXITYAI_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:PERPLEXITYAI_API_KEY::" },
      # { name = "GITHUB_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:GITHUB_API_KEY::" },
      # { name = "DEEPSEEK_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:DEEPSEEK_API_KEY::" },
      # { name = "AI21_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:AI21_API_KEY::" },
      # { name = "LANGSMITH_API_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:LANGSMITH_API_KEY::" },
      { name = "LANGFUSE_SECRET_KEY", valueFrom = "${aws_secretsmanager_secret_version.llm_api_keys.arn}:LANGFUSE_SECRET_KEY::" },
    ]

    portMappings = [{ containerPort = 4000, protocol = "tcp" }]

    healthCheck = {
      command  = ["CMD-SHELL", "exit 0"]
      interval = 30
      timeout  = 5
      retries  = 3
    }
  }

  middleware_container_definition = {
    name      = "MiddlewareContainer"
    image     = "${data.aws_ecr_repository.middleware.repository_url}:${var.middleware_version}"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.middleware.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "Middleware"
      }
    }

    environment = [
      { name = "OKTA_ISSUER", value = var.okta_issuer },
      { name = "OKTA_AUDIENCE", value = var.okta_audience },
    ]

    secrets = [
      { name = "DATABASE_MIDDLEWARE_URL", valueFrom = aws_secretsmanager_secret.db_url.arn },
      { name = "MASTER_KEY", valueFrom = "${aws_secretsmanager_secret.master_salt.arn}:LITELLM_MASTER_KEY::" },
    ]

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    healthCheck = {
      command  = ["CMD-SHELL", "exit 0"]
      interval = 30
      timeout  = 5
      retries  = 3
    }
  }

  container_definitions = jsonencode(concat(
    [local.litellm_container_definition],
    var.enable_middleware ? [local.middleware_container_definition] : []
  ))
}

# ── ECS service (via module) ──────────────────────────────────────────────────

module "service" {
  source = "../../../../modules/ecs-service"

  name        = "${var.name}-litellm"
  cluster_arn = module.cluster.cluster_arn

  vpc_id             = local.networking_vpc_id
  private_subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
  security_group_ids = [aws_security_group.ecs_task.id]

  container_definitions = local.container_definitions
  cpu                   = local.cpu_units
  memory                = local.memory_mib
  cpu_architecture      = local.cpu_architecture

  task_execution_role_arn = module.iam.execution_role_arn
  task_role_arn           = module.iam.task_role_arn

  desired_count = var.desired_capacity
  min_count     = var.min_capacity
  max_count     = var.max_capacity

  cpu_target_utilization_percent    = var.cpu_target_utilization_percent
  memory_target_utilization_percent = var.memory_target_utilization_percent

  load_balancers = concat(
    [
      {
        target_group_arn = module.alb.target_group_arns["litellm"]
        container_name   = "LiteLLMContainer"
        container_port   = 4000
      }
    ],
    var.enable_middleware ? [
      {
        target_group_arn = module.alb.target_group_arns["middleware"]
        container_name   = "MiddlewareContainer"
        container_port   = 3000
      }
    ] : []
  )

  depends_on = [
    module.rds,
    module.redis,
    module.alb,
    aws_secretsmanager_secret_version.master_salt,
    aws_secretsmanager_secret_version.db_url,
    aws_secretsmanager_secret_version.llm_api_keys,
    aws_secretsmanager_secret_version.redis_auth,
  ]
}

# ── Lambda: manual ECS scale to 0/0 or 1/1 (cost pause / resume) ─────────────

module "ecs_scale_toggle" {
  source = "../../../../modules/ecs-capacity-toggle-lambda"

  name             = "${var.name}-litellm"
  ecs_cluster_name = module.cluster.cluster_name
  ecs_service_name = module.service.service_name
  max_task_count   = var.max_capacity

  depends_on = [module.service]
}

# ── ALB Listener rules (LiteLLM routing) ─────────────────────────────────────
# Rules on the HTTPS listener.  Mirror set on HTTP listener when CloudFront
# is enabled (CloudFront → ALB uses HTTP + X-CloudFront-Secret header).

locals {
  # When CloudFront is enabled we check the secret header before forwarding.
  cf_secret = var.use_cloudfront ? "cf-${module.cdn[0].origin_secret}" : ""

  # Paths routed to the Middleware container (port 3000)
  middleware_rules = var.enable_middleware ? {
    bedrock_models       = { priority = 16, paths = ["/bedrock/model/*"], methods = ["POST", "GET", "PUT"] }
    openai_completions   = { priority = 15, paths = ["/v1/chat/completions"], methods = ["POST", "GET", "PUT"] }
    chat_completions     = { priority = 14, paths = ["/chat/completions"], methods = ["POST", "GET", "PUT"] }
    user_new             = { priority = 13, paths = ["/user/new"], methods = ["POST", "GET", "PUT"] }
    key_generate         = { priority = 12, paths = ["/key/generate"], methods = ["POST", "GET", "PUT"] }
    session_ids          = { priority = 11, paths = ["/session-ids"], methods = ["POST", "GET", "PUT"] }
    bedrock_liveliness   = { priority = 10, paths = ["/bedrock/health/liveliness"], methods = ["POST", "GET", "PUT"] }
    bedrock_chat_history = { priority = 9, paths = ["/bedrock/chat-history"], methods = ["POST", "GET", "PUT"] }
    chat_history         = { priority = 8, paths = ["/chat-history"], methods = ["POST", "GET", "PUT"] }
  } : {}
}

# Middleware routing rules (HTTPS)
resource "aws_lb_listener_rule" "middleware_https" {
  for_each = local.middleware_rules

  listener_arn = module.alb.https_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["middleware"]
  }

  condition {
    path_pattern { values = each.value.paths }
  }

  condition {
    http_request_method { values = each.value.methods }
  }
}

# CloudFront: health-check bypass (no header required, highest priority)
resource "aws_lb_listener_rule" "cf_health_bypass_https" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.https_listener_arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["litellm"]
  }

  condition {
    path_pattern {
      values = ["/", "/health", "/health/liveliness", "/bedrock/health/liveliness"]
    }
  }
}

# CloudFront: allow requests carrying the origin secret header
resource "aws_lb_listener_rule" "cf_auth_https" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.https_listener_arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["litellm"]
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [local.cf_secret]
    }
  }
}

# CloudFront: reject direct access to all other paths
resource "aws_lb_listener_rule" "cf_reject_https" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.https_listener_arn
  priority     = 6

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"Direct access is not allowed.\"}"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["/*"] }
  }
}

# Catch-all forward to LiteLLM (used when CloudFront is disabled)
resource "aws_lb_listener_rule" "catch_all_https" {
  listener_arn = module.alb.https_listener_arn
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["litellm"]
  }

  condition {
    path_pattern { values = ["/*"] }
  }
}

# HTTP mirror rules (only when CloudFront is enabled — CF uses HTTP internally)
resource "aws_lb_listener_rule" "middleware_http" {
  for_each = var.use_cloudfront ? local.middleware_rules : {}

  listener_arn = module.alb.http_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["middleware"]
  }

  condition {
    path_pattern { values = each.value.paths }
  }

  condition {
    http_request_method { values = each.value.methods }
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [local.cf_secret]
    }
  }
}

resource "aws_lb_listener_rule" "cf_health_bypass_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.http_listener_arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["litellm"]
  }

  condition {
    path_pattern {
      values = ["/", "/health", "/health/liveliness", "/bedrock/health/liveliness"]
    }
  }
}

resource "aws_lb_listener_rule" "cf_catch_all_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.http_listener_arn
  priority     = 98

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arns["litellm"]
  }

  condition {
    path_pattern { values = ["/*"] }
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [local.cf_secret]
    }
  }
}

resource "aws_lb_listener_rule" "cf_reject_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = module.alb.http_listener_arn
  priority     = 99

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"Direct access is not allowed.\"}"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["/*"] }
  }
}
