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

LITELLM_REPOSITORY="${APP_NAME:-${ECR_LITELLM_REPOSITORY:-litellm}}"
MIDDLEWARE_REPOSITORY="${ECR_MIDDLEWARE_REPOSITORY:-middleware}"
BUILD_FROM_SOURCE="$(echo "${BUILD_FROM_SOURCE:-false}" | tr '[:upper:]' '[:lower:]')"
ENABLE_MIDDLEWARE="$(echo "${ENABLE_MIDDLEWARE:-${TF_VAR_enable_middleware:-false}}" | tr '[:upper:]' '[:lower:]')"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
LITELLM_VERSION="${LITELLM_VERSION:-${TF_VAR_litellm_version:-latest}}"
MIDDLEWARE_VERSION="${MIDDLEWARE_VERSION:-${TF_VAR_middleware_version:-latest}}"
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
LITELLM_IMAGE_URI="${ECR_REGISTRY}/${LITELLM_REPOSITORY}:${LITELLM_VERSION}"
MIDDLEWARE_IMAGE_URI="${ECR_REGISTRY}/${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}"
LITELLM_BUILD_CONTEXT="."
MIDDLEWARE_BUILD_CONTEXT="middleware"

ensure_repository() {
    local repository_name="$1"

    if aws ecr describe-repositories --repository-names "$repository_name" >/dev/null 2>&1; then
        echo "Repository $repository_name already exists"
        return
    fi

    echo "Creating ECR repository $repository_name"
    aws ecr create-repository \
        --repository-name "$repository_name" \
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
    LITELLM_BUILD_CONTEXT="litellm-source"
}

publish_environment() {
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        {
            echo "LITELLM_VERSION=${LITELLM_VERSION}"
            echo "MIDDLEWARE_VERSION=${MIDDLEWARE_VERSION}"
            echo "TF_VAR_litellm_version=${LITELLM_VERSION}"
            echo "TF_VAR_middleware_version=${MIDDLEWARE_VERSION}"
            echo "TF_VAR_architecture=${TERRAFORM_ARCHITECTURE}"
            echo "TF_VAR_enable_middleware=${ENABLE_MIDDLEWARE}"
            echo "ECR_LITELLM_IMAGE_URI=${LITELLM_IMAGE_URI}"
            if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
                echo "ECR_MIDDLEWARE_IMAGE_URI=${MIDDLEWARE_IMAGE_URI}"
            fi
        } >> "$GITHUB_ENV"
    fi
}

validate_manifest_architecture() {
    local image_uri="$1"
    local expected_arch
    local archs

    expected_arch="$(echo "$DOCKER_ARCH" | cut -d'/' -f2)"
    archs="$(docker manifest inspect "$image_uri" 2>/dev/null | jq -r '.manifests[].platform.architecture' 2>/dev/null | sort -u | tr '\n' ' ')"

    if [[ -z "$archs" ]]; then
        echo "Warning: could not inspect manifest list for $image_uri (single-arch image is still valid)."
        return
    fi

    if [[ " $archs " != *" $expected_arch "* ]]; then
        echo "Error: $image_uri does not include expected architecture '$expected_arch'. Found: $archs"
        exit 1
    fi

    echo "Validated manifest arch for $image_uri: $archs"
}

echo "Preparing LiteLLM image build"
echo "LITELLM_REPOSITORY=${LITELLM_REPOSITORY}"
echo "MIDDLEWARE_REPOSITORY=${MIDDLEWARE_REPOSITORY}"
echo "LITELLM_VERSION=${LITELLM_VERSION}"
echo "MIDDLEWARE_VERSION=${MIDDLEWARE_VERSION}"
echo "ENABLE_MIDDLEWARE=${ENABLE_MIDDLEWARE}"
echo "DOCKER_ARCH=${DOCKER_ARCH}"
echo "ARCH=${ARCH}"

ensure_repository "$LITELLM_REPOSITORY"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    ensure_repository "$MIDDLEWARE_REPOSITORY"
fi
prepare_build_context
publish_environment

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker build \
    --platform "$DOCKER_ARCH" \
    --build-arg "LITELLM_VERSION=${LITELLM_VERSION}" \
    -t "${LITELLM_REPOSITORY}:${LITELLM_VERSION}" \
    "$LITELLM_BUILD_CONTEXT"

docker tag "${LITELLM_REPOSITORY}:${LITELLM_VERSION}" "$LITELLM_IMAGE_URI"
docker push "$LITELLM_IMAGE_URI"
validate_manifest_architecture "$LITELLM_IMAGE_URI"

if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    docker build \
        --platform "$DOCKER_ARCH" \
        -t "${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}" \
        "$MIDDLEWARE_BUILD_CONTEXT"

    docker tag "${MIDDLEWARE_REPOSITORY}:${MIDDLEWARE_VERSION}" "$MIDDLEWARE_IMAGE_URI"
    docker push "$MIDDLEWARE_IMAGE_URI"
    validate_manifest_architecture "$MIDDLEWARE_IMAGE_URI"
else
    echo "Skipping middleware image build/push because ENABLE_MIDDLEWARE=false"
fi

echo "Built and pushed ${LITELLM_IMAGE_URI}"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    echo "Built and pushed ${MIDDLEWARE_IMAGE_URI}"
fi
