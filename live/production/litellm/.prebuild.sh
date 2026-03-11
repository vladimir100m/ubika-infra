#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
    set -a
    source .env
    set +a
    echo "Loaded environment variables from .env file"
else
    echo ".env not found, using workflow environment/defaults"
fi

APP_NAME="${APP_NAME:-${ECR_LITELLM_REPOSITORY:-litellm}}"
BUILD_FROM_SOURCE="$(echo "${BUILD_FROM_SOURCE:-false}" | tr '[:upper:]' '[:lower:]')"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
LITELLM_VERSION="${LITELLM_VERSION:-${TF_VAR_litellm_version:-latest}}"
CPU_ARCHITECTURE="${CPU_ARCHITECTURE:-}"

if [[ "$LITELLM_VERSION" == "placeholder" ]]; then
    echo "LITELLM_VERSION must be set via .env, TF_VAR_litellm_version, or environment variables"
    exit 1
fi

if [[ -n "$CPU_ARCHITECTURE" ]]; then
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
    case "$(uname -m)" in
        x86_64)
            ARCH="x86"
            ;;
        arm64|aarch64)
            ARCH="arm"
            ;;
        *)
            echo "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
fi

case "$ARCH" in
    "x86")
        DOCKER_ARCH="linux/amd64"
        TERRAFORM_ARCHITECTURE="x86"
        ;;
    "arm")
        DOCKER_ARCH="linux/arm64"
        TERRAFORM_ARCHITECTURE="arm"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${APP_NAME}:${LITELLM_VERSION}"
BUILD_CONTEXT="."

ensure_repository() {
    if aws ecr describe-repositories --repository-names "$APP_NAME" >/dev/null 2>&1; then
        echo "Repository $APP_NAME already exists"
        return
    fi

    echo "Creating ECR repository $APP_NAME"
    aws ecr create-repository \
        --repository-name "$APP_NAME" \
        --tags Key=project,Value=ubika-infra Key=workload,Value=litellm >/dev/null
}

prepare_build_context() {
    if [[ "$BUILD_FROM_SOURCE" != "true" ]]; then
        return
    fi

    echo "Building LiteLLM from source for version ${LITELLM_VERSION}"
    rm -rf litellm-source
    mkdir -p litellm-source
    curl -fsSL "https://github.com/BerriAI/litellm/archive/refs/tags/${LITELLM_VERSION}.tar.gz" \
        | tar -xz -C litellm-source --strip-components=1
    BUILD_CONTEXT="litellm-source"
}

publish_environment() {
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        {
            echo "LITELLM_VERSION=${LITELLM_VERSION}"
            echo "TF_VAR_litellm_version=${LITELLM_VERSION}"
            echo "TF_VAR_architecture=${TERRAFORM_ARCHITECTURE}"
            echo "ECR_LITELLM_IMAGE_URI=${IMAGE_URI}"
        } >> "$GITHUB_ENV"
    fi
}

echo "Preparing LiteLLM image build"
echo "APP_NAME=${APP_NAME}"
echo "LITELLM_VERSION=${LITELLM_VERSION}"
echo "DOCKER_ARCH=${DOCKER_ARCH}"
echo "ARCH=${ARCH}"

ensure_repository
prepare_build_context
publish_environment

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker build \
    --platform "$DOCKER_ARCH" \
    --build-arg "LITELLM_VERSION=${LITELLM_VERSION}" \
    -t "${APP_NAME}:${LITELLM_VERSION}" \
    "$BUILD_CONTEXT"

docker tag "${APP_NAME}:${LITELLM_VERSION}" "$IMAGE_URI"
docker push "$IMAGE_URI"

echo "Built and pushed ${IMAGE_URI}"
