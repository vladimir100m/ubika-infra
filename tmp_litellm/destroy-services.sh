#!/bin/bash
set -aeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./destroy-services.sh --services ECS,WAF[,RDS,REDIS,NAT,VPCE,CLOUDFRONT,ALB,EKS]
  ./destroy-services.sh --free-tier

Notes:
- This script intentionally excludes S3, ECR, and Secrets Manager resources.
- It reuses the same Terraform state and variables as undeploy.sh.
USAGE
}

if [ ! -f "config/config.yaml" ]; then
  echo "config/config.yaml does not exist, aborting"
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "Error: .env file missing, aborting."
  exit 1
fi

SERVICES_INPUT=""
FREE_TIER="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --services|-s)
      SERVICES_INPUT="$2"
      shift 2
      ;;
    --free-tier)
      FREE_TIER="true"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
 done

if [[ "$FREE_TIER" != "true" && -z "$SERVICES_INPUT" ]]; then
  usage
  exit 1
fi

aws_region=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')

echo "$aws_region"

APP_NAME=litellm
MIDDLEWARE_APP_NAME=middleware
LOG_BUCKET_STACK_NAME="log-bucket-stack"
MAIN_STACK_NAME="litellm-stack"

# Load environment variables from .env file
source .env

if [[ (-z "$LITELLM_VERSION") || ("$LITELLM_VERSION" == "placeholder") ]]; then
  echo "LITELLM_VERSION must be set in .env file"
  exit 1
fi

if [ -n "$CPU_ARCHITECTURE" ]; then
  case "$CPU_ARCHITECTURE" in
    "x86"|"arm")
      ARCH="$CPU_ARCHITECTURE"
      ;;
    *)
      echo "Error: CPU_ARCHITECTURE must be either 'x86' or 'arm'"
      exit 1
      ;;
  esac
else
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      ARCH="x86"
      ;;
    arm64)
      ARCH="arm"
      ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
fi

cd litellm-s3-log-bucket-terraform
LOG_BUCKET_NAME=$(terraform output -raw LogBucketName)
LOG_BUCKET_ARN=$(terraform output -raw LogBucketArn)
cd ..

cd litellm-terraform-stack

export TF_VAR_deployment_platform=$DEPLOYMENT_PLATFORM
export TF_VAR_name=$MAIN_STACK_NAME
export TF_VAR_vpc_id=$EXISTING_VPC_ID
export TF_VAR_log_bucket_arn=$LOG_BUCKET_ARN
export TF_VAR_litellm_version=$LITELLM_VERSION
export TF_VAR_openai_api_key=$OPENAI_API_KEY
export TF_VAR_azure_openai_api_key=$AZURE_OPENAI_API_KEY
export TF_VAR_azure_api_key=$AZURE_API_KEY
export TF_VAR_anthropic_api_key=$ANTHROPIC_API_KEY
export TF_VAR_public_load_balancer=$PUBLIC_LOAD_BALANCER
export TF_VAR_existing_cluster_name=$EXISTING_EKS_CLUSTER_NAME
export TF_VAR_groq_api_key=$GROQ_API_KEY
export TF_VAR_cohere_api_key=$COHERE_API_KEY
export TF_VAR_co_api_key=$CO_API_KEY
export TF_VAR_hf_token=$HF_TOKEN
export TF_VAR_huggingface_api_key=$HUGGINGFACE_API_KEY
export TF_VAR_databricks_api_key=$DATABRICKS_API_KEY
export TF_VAR_gemini_api_key=$GEMINI_API_KEY
export TF_VAR_codestral_api_key=$CODESTRAL_API_KEY
export TF_VAR_mistral_api_key=$MISTRAL_API_KEY
export TF_VAR_azure_ai_api_key=$AZURE_AI_API_KEY
export TF_VAR_nvidia_nim_api_key=$NVIDIA_NIM_API_KEY
export TF_VAR_xai_api_key=$XAI_API_KEY
export TF_VAR_perplexityai_api_key=$PERPLEXITYAI_API_KEY
export TF_VAR_github_api_key=$GITHUB_API_KEY
export TF_VAR_deepseek_api_key=$DEEPSEEK_API_KEY
export TF_VAR_ai21_api_key=$AI21_API_KEY
export TF_VAR_langsmith_api_key=$LANGSMITH_API_KEY
export TF_VAR_langsmith_project=$LANGSMITH_PROJECT
export TF_VAR_langsmith_default_run_name=$LANGSMITH_DEFAULT_RUN_NAME
export TF_VAR_okta_audience=$OKTA_AUDIENCE
export TF_VAR_okta_issuer=$OKTA_ISSUER
export TF_VAR_record_name=$RECORD_NAME
export TF_VAR_hosted_zone_name=$HOSTED_ZONE_NAME
export TF_VAR_create_private_hosted_zone_in_existing_vpc=$CREATE_PRIVATE_HOSTED_ZONE_IN_EXISTING_VPC
export TF_VAR_certificate_arn=$CERTIFICATE_ARN
export TF_VAR_architecture=$ARCH
export TF_VAR_disable_outbound_network_access=$DISABLE_OUTBOUND_NETWORK_ACCESS
export TF_VAR_desired_capacity=$DESIRED_CAPACITY
export TF_VAR_min_capacity=$MIN_CAPACITY
export TF_VAR_max_capacity=$MAX_CAPACITY
export TF_VAR_cpu_target_utilization_percent=$ECS_CPU_TARGET_UTILIZATION_PERCENTAGE
export TF_VAR_memory_target_utilization_percent=$ECS_MEMORY_TARGET_UTILIZATION_PERCENTAGE
export TF_VAR_vcpus=$ECS_VCPUS
export TF_VAR_install_add_ons_in_existing_eks_cluster=$INSTALL_ADD_ONS_IN_EXISTING_EKS_CLUSTER
export TF_VAR_arm_instance_type=$EKS_ARM_INSTANCE_TYPE
export TF_VAR_x86_instance_type=$EKS_X86_INSTANCE_TYPE
export TF_VAR_arm_ami_type=$EKS_ARM_AMI_TYPE
export TF_VAR_x86_ami_type=$EKS_X86_AMI_TYPE
export TF_VAR_create_vpc_endpoints_in_existing_vpc=$CREATE_VPC_ENDPOINTS_IN_EXISTING_VPC
export TF_VAR_ecrLitellmRepository=$APP_NAME
export TF_VAR_ecrMiddlewareRepository=$MIDDLEWARE_APP_NAME
export TF_VAR_rds_instance_class=$RDS_INSTANCE_CLASS
export TF_VAR_rds_allocated_storage=$RDS_ALLOCATED_STORAGE_GB
export TF_VAR_rds_multi_az=$RDS_MULTI_AZ
export TF_VAR_rds_performance_insights_enabled=$RDS_PERFORMANCE_INSIGHTS_ENABLED
export TF_VAR_rds_monitoring_interval=$RDS_MONITORING_INTERVAL
export TF_VAR_redis_node_type=$REDIS_NODE_TYPE
export TF_VAR_redis_num_cache_clusters=$REDIS_NUM_CACHE_CLUSTERS
export TF_VAR_disable_swagger_page=$DISABLE_SWAGGER_PAGE
export TF_VAR_disable_admin_ui=$DISABLE_ADMIN_UI
export TF_VAR_langfuse_public_key=$LANGFUSE_PUBLIC_KEY
export TF_VAR_langfuse_secret_key=$LANGFUSE_SECRET_KEY
export TF_VAR_use_route53=$USE_ROUTE53
export TF_VAR_use_cloudfront=$USE_CLOUDFRONT
export TF_VAR_cloudfront_price_class=$CLOUDFRONT_PRICE_CLASS

if [ -n "${LANGFUSE_HOST}" ]; then
  export TF_VAR_langfuse_host=$LANGFUSE_HOST
fi

if [ -n "$EXISTING_EKS_CLUSTER_NAME" ]; then
  export TF_VAR_create_cluster="false"
else
  export TF_VAR_create_cluster="true"
fi

cat > backend.hcl << EOF
bucket  = "${TERRAFORM_S3_BUCKET_NAME}"
key     = "terraform-unified.tfstate"
region  = "${aws_region}"
encrypt = true
EOF

echo "Generated backend.hcl configuration"

terraform init -backend-config=backend.hcl

state_list=$(terraform state list)
exclude_pattern='aws_s3_|aws_ecr_|aws_secretsmanager_|aws_vpc_endpoint\.s3_gateway|aws_vpc_endpoint\.ecr(\.|_)|aws_vpc_endpoint\.secretsmanager'

collect_targets() {
  local include_pattern="$1"
  echo "$state_list" | grep -E "$include_pattern" | grep -Ev "$exclude_pattern" || true
}

services=()
if [[ "$FREE_TIER" == "true" ]]; then
  deployment_platform_upper=$(echo "$DEPLOYMENT_PLATFORM" | tr '[:lower:]' '[:upper:]')
  if [[ "$deployment_platform_upper" == "ECS" ]]; then
    services=("ecs" "waf" "rds" "redis" "nat" "vpc_endpoints" "cloudfront")
  else
    services=("eks" "waf" "rds" "redis" "nat" "vpc_endpoints")
  fi
else
  IFS=',' read -r -a services <<< "$SERVICES_INPUT"
  for i in "${!services[@]}"; do
    services[$i]="$(echo "${services[$i]}" | tr '[:upper:]' '[:lower:]' | xargs)"
  done
fi

targets=()
for service in "${services[@]}"; do
  case "$service" in
    ecs)
      targets+=( $(collect_targets '^module\.ecs_cluster\[0\]\.(aws_ecs_|aws_lb_|aws_lb_listener|aws_lb_listener_rule|aws_lb_target_group|aws_security_group|aws_security_group_rule|aws_cloudwatch_log_group|aws_iam_|aws_appautoscaling_|tls_|random_password)') )
      ;;
    alb)
      targets+=( $(collect_targets '^module\.ecs_cluster\[0\]\.(aws_lb_|aws_lb_listener|aws_lb_listener_rule|aws_lb_target_group|aws_security_group\.alb_sg|aws_security_group_rule\.alb_)') )
      ;;
    waf)
      targets+=( $(collect_targets '^module\.base\.aws_wafv2_web_acl\.|^module\.ecs_cluster\[0\]\.aws_wafv2_web_acl_association\.') )
      ;;
    rds)
      targets+=( $(collect_targets '^module\.base\.(aws_db_instance|aws_db_subnet_group|aws_db_parameter_group|aws_security_group\.db_sg|random_password\.db_password_main)') )
      ;;
    redis)
      targets+=( $(collect_targets '^module\.base\.(aws_elasticache_|aws_security_group\.redis_sg|random_password\.redis_password_main)') )
      ;;
    nat)
      targets+=( $(collect_targets '^module\.base\.(aws_nat_gateway|aws_eip\.nat|aws_route_table\.private_with_nat|aws_route_table_association\.private|aws_cloudwatch_log_group\.vpc_flow_logs|aws_flow_log\.this)') )
      ;;
    vpc_endpoints|vpce)
      targets+=( $(collect_targets '^module\.base\.(aws_vpc_endpoint|aws_security_group\.vpc_endpoints_sg)') )
      ;;
    cloudfront)
      targets+=( $(collect_targets '^module\.ecs_cluster\[0\]\.(aws_cloudfront_distribution|random_password\.cloudfront_secret)') )
      ;;
    eks)
      targets+=( $(collect_targets '^module\.eks_cluster\[0\]\.(aws_eks_|aws_iam_|aws_security_group|aws_security_group_rule|aws_kms_|aws_iam_openid_connect_provider)') )
      ;;
    *)
      echo "Unknown service: $service"
      exit 1
      ;;
  esac
 done

# De-duplicate targets
unique_targets=()
if [ ${#targets[@]} -gt 0 ]; then
  while IFS= read -r t; do
    unique_targets+=("$t")
  done < <(printf '%s\n' "${targets[@]}" | awk '!seen[$0]++')
fi

if [ ${#unique_targets[@]} -eq 0 ]; then
  echo "No matching targets found for selected services."
  exit 0
fi

echo "Destroying targets:"
printf '%s\n' "${unique_targets[@]}"

tf_targets=()
for t in "${unique_targets[@]}"; do
  tf_targets+=("-target=${t}")
done

terraform destroy -auto-approve "${tf_targets[@]}"
