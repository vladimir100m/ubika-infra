#!/usr/bin/env bash
# .github/scripts/build-image.sh
set -euo pipefail

TARGET_FOLDER="${1:?Target folder is required (e.g., live/production/agents)}"

if [[ ! -d "$TARGET_FOLDER" ]]; then
  echo "Error: directory not found: $TARGET_FOLDER" >&2
  exit 1
fi

# Terraform-only layers (e.g. networking) have no image — skip build/push cleanly.
if [[ ! -f "$TARGET_FOLDER/Dockerfile" ]] && [[ ! -f "$TARGET_FOLDER/.postbuild.sh" ]]; then
  echo "Skipping image build: no Dockerfile or .postbuild.sh in ${TARGET_FOLDER}"
  exit 0
fi

# 1. Load Environment
if [[ -f .env ]]; then
    set -a; source .env; set +a
fi

# 2. Extract Repo Name from Folder (e.g., live/production/agents -> ubika-agents)
# This standardizes naming across the monorepo
FOLDER_NAME=$(basename "$TARGET_FOLDER")
DEFAULT_REPO="ubika-${FOLDER_NAME}"

# 3. Variables & Defaults
AWS_REGION="${AWS_REGION:-us-east-1}"
CPU_ARCHITECTURE="${CPU_ARCHITECTURE:-linux/amd64}"
# Use Git SHA for generic images, fall back to LiteLLM versioning for that specific repo
IMAGE_TAG="${GITHUB_SHA:-latest}"

# Specialized LiteLLM logic (only if the folder contains 'litellm')
if [[ "$TARGET_FOLDER" == *"litellm"* ]]; then
    REPO_NAME="${ECR_LITELLM_REPOSITORY:-litellm}"
    IMAGE_TAG="${LITELLM_VERSION:-${TF_VAR_litellm_version:-v1.73.0}}"
else
    REPO_NAME="${DEFAULT_REPO}"
fi

# 4. Normalization Helpers
normalize_docker_arch() {
    case "$1" in
        x86|x86_64|amd64|linux/amd64) echo "linux/amd64" ;;
        arm|arm64|aarch64|linux/arm64) echo "linux/arm64" ;;
        *) echo "$1" ;;
    esac
}

# 5. Infrastructure Checks
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"
DOCKER_ARCH="$(normalize_docker_arch "$CPU_ARCHITECTURE")"

ensure_repository() {
    aws ecr describe-repositories --repository-names "$1" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$1" --tags Key=project,Value=ubika >/dev/null
}

# 6. Build Logic
build_and_push() {
    echo "--- Building $IMAGE_URI for $DOCKER_ARCH ---"
    
    # Check for .postbuild.sh override
    if [[ -f "$TARGET_FOLDER/.postbuild.sh" ]]; then
        echo "Running custom postbuild script for $TARGET_FOLDER"
        bash "$TARGET_FOLDER/.postbuild.sh" "$IMAGE_URI"
    else
        # Standard Docker Build
        docker buildx build \
            --platform "$DOCKER_ARCH" \
            --tag "$IMAGE_URI" \
            --push \
            "$TARGET_FOLDER"
    fi
}

# 7. Execution
ensure_repository "$REPO_NAME"

aws ecr get-login-password --region "$AWS_REGION" | \
docker login --username AWS --password-stdin "$ECR_REGISTRY"

build_and_push

# Export for GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "IMAGE_URI_${FOLDER_NAME^^}=$IMAGE_URI" >> "$GITHUB_ENV"
    echo "TF_VAR_${FOLDER_NAME}_image_tag=$IMAGE_TAG" >> "$GITHUB_ENV"
fi