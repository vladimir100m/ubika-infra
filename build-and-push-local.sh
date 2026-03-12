#!/usr/bin/env bash
set -euo pipefail

# Local build and push script for LiteLLM and Middleware images
# Usage: ./build-and-push-local.sh [--middleware] [--litellm-version <version>] [--middleware-version <version>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/live/production/litellm"

# Defaults
LITELLM_VERSION="${LITELLM_VERSION:-latest}"
MIDDLEWARE_VERSION="${MIDDLEWARE_VERSION:-latest}"
ENABLE_MIDDLEWARE="false"
AWS_REGION="${AWS_REGION:-us-east-1}"
LITELLM_REPOSITORY="litellm"
MIDDLEWARE_REPOSITORY="middleware"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --middleware)
      ENABLE_MIDDLEWARE="true"
      shift
      ;;
    --litellm-version)
      LITELLM_VERSION="$2"
      shift 2
      ;;
    --middleware-version)
      MIDDLEWARE_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./build-and-push-local.sh [--middleware] [--litellm-version <version>] [--middleware-version <version>]"
      exit 1
      ;;
  esac
done

# Detect local architecture
case "$(uname -m)" in
  x86_64)
    ARCH="x86"
    DOCKER_ARCH="linux/amd64"
    ;;
  arm64|aarch64)
    ARCH="arm"
    DOCKER_ARCH="linux/arm64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

echo "=========================================="
echo "Local Build & Push Configuration"
echo "=========================================="
echo "Architecture: $ARCH ($DOCKER_ARCH)"
echo "LiteLLM Version: $LITELLM_VERSION"
echo "Middleware Enabled: $ENABLE_MIDDLEWARE"
echo "Middleware Version: $MIDDLEWARE_VERSION"
echo "AWS Region: $AWS_REGION"
echo "=========================================="

# Get AWS Account ID
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

LITELLM_IMAGE_URI="${ECR_REGISTRY}/${LITELLM_REPOSITORY}:${LITELLM_VERSION}"
MIDDLEWARE_IMAGE_URI="${ECR_REGISTRY}/${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}"

echo "ECR Registry: $ECR_REGISTRY"
echo "LiteLLM Image: $LITELLM_IMAGE_URI"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
  echo "Middleware Image: $MIDDLEWARE_IMAGE_URI"
fi
echo ""

# Ensure repositories exist
ensure_repository() {
  local repository_name="$1"

  if aws ecr describe-repositories --repository-names "$repository_name" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "✓ Repository $repository_name already exists"
    return
  fi

  echo "Creating ECR repository $repository_name..."
  aws ecr create-repository \
    --repository-name "$repository_name" \
    --region "$AWS_REGION" \
    --tags Key=project,Value=ubika-infra Key=workload,Value=litellm >/dev/null
  echo "✓ Created repository $repository_name"
}

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
echo "✓ ECR login successful"
echo ""

# Ensure repositories exist
echo "Checking ECR repositories..."
ensure_repository "$LITELLM_REPOSITORY"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
  ensure_repository "$MIDDLEWARE_REPOSITORY"
fi
echo ""

# Build and push LiteLLM
echo "Building LiteLLM image..."
docker build \
  --platform "$DOCKER_ARCH" \
  --build-arg "LITELLM_VERSION=${LITELLM_VERSION}" \
  --build-arg "TARGETPLATFORM=${DOCKER_ARCH}" \
  -t "${LITELLM_REPOSITORY}:${LITELLM_VERSION}" \
  .

echo "✓ LiteLLM image built successfully"
echo ""

echo "Tagging LiteLLM image as $LITELLM_IMAGE_URI..."
docker tag "${LITELLM_REPOSITORY}:${LITELLM_VERSION}" "$LITELLM_IMAGE_URI"
echo "✓ Tagged"
echo ""

echo "Pushing LiteLLM image to ECR..."
docker push "$LITELLM_IMAGE_URI"
echo "✓ LiteLLM image pushed successfully"
echo ""

# Build and push Middleware if enabled
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
  echo "Building Middleware image..."
  docker build \
    --platform "$DOCKER_ARCH" \
    --build-arg "TARGETPLATFORM=${DOCKER_ARCH}" \
    -t "${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}" \
    middleware

  echo "✓ Middleware image built successfully"
  echo ""

  echo "Tagging Middleware image as $MIDDLEWARE_IMAGE_URI..."
  docker tag "${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}" "$MIDDLEWARE_IMAGE_URI"
  echo "✓ Tagged"
  echo ""

  echo "Pushing Middleware image to ECR..."
  docker push "$MIDDLEWARE_IMAGE_URI"
  echo "✓ Middleware image pushed successfully"
  echo ""
fi

echo "=========================================="
echo "✓ Build & Push Completed Successfully!"
echo "=========================================="
echo "LiteLLM: $LITELLM_IMAGE_URI"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
  echo "Middleware: $MIDDLEWARE_IMAGE_URI"
fi
echo ""
