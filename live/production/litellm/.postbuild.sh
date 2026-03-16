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
AWS_REGION="${AWS_REGION}"
LITELLM_VERSION="${LITELLM_VERSION:-${TF_VAR_litellm_version:-litellm_stable_release_branch-v1.73.0-stable}}"
MIDDLEWARE_VERSION="${MIDDLEWARE_VERSION:-${TF_VAR_middleware_version:-latest}}"
CPU_ARCHITECTURE="${CPU_ARCHITECTURE:-${DOCKER_ARCH:-linux/amd64}}"

normalize_bool() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

if [[ "$LITELLM_VERSION" == "placeholder" ]]; then
    echo "LITELLM_VERSION must be set via .env, TF_VAR_litellm_version, or environment variables"
    exit 1
fi

DOCKER_ARCH="$CPU_ARCHITECTURE"
TERRAFORM_ARCHITECTURE="${TF_VAR_architecture:-x86}"

case "$DOCKER_ARCH" in
    linux/amd64)
        inferred_terraform_architecture="x86"
        ;;
    linux/arm64)
        inferred_terraform_architecture="arm"
        ;;
    *)
        echo "Unsupported DOCKER_ARCH value: $DOCKER_ARCH"
        exit 1
        ;;
esac

if [[ -z "${TF_VAR_architecture:-}" ]]; then
    TERRAFORM_ARCHITECTURE="$inferred_terraform_architecture"
elif [[ "$TF_VAR_architecture" != "$inferred_terraform_architecture" ]]; then
    echo "Error: TF_VAR_architecture=${TF_VAR_architecture} does not match DOCKER_ARCH=${DOCKER_ARCH}"
    exit 1
fi

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

build_and_push_image() {
    local repository="$1"
    local version="$2"
    local context="$3"
    local image_uri="$4"
    local include_litellm_version_arg="${5:-false}"

    local build_args=(
        --platform "$DOCKER_ARCH"
    )

    if [[ "$include_litellm_version_arg" == "true" ]]; then
        build_args+=(--build-arg "LITELLM_VERSION=${version}")
    fi

    docker buildx build \
        "${build_args[@]}" \
        --pull \
        --tag "$image_uri" \
        --push \
        "$context"
    validate_manifest_architecture "$image_uri"
}

validate_manifest_architecture() {
    local image_uri="$1"
    local expected_arch
    local archs

    expected_arch="$(echo "$DOCKER_ARCH" | cut -d'/' -f2)"
    archs="$({
        docker manifest inspect "$image_uri" 2>/dev/null \
            | jq -r '(.manifests[]?.platform.architecture), (.architecture? // empty), (.config.platform.architecture? // empty)' 2>/dev/null \
            | sort -u \
            | tr '\n' ' '
    } || true)"

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
echo "ARCH=${TERRAFORM_ARCHITECTURE}"

ensure_repository "$LITELLM_REPOSITORY"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    ensure_repository "$MIDDLEWARE_REPOSITORY"
fi
prepare_build_context
publish_environment

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

build_and_push_image \
    "$LITELLM_REPOSITORY" \
    "$LITELLM_VERSION" \
    "$LITELLM_BUILD_CONTEXT" \
    "$LITELLM_IMAGE_URI" \
    "true"

if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    build_and_push_image \
        "$MIDDLEWARE_REPOSITORY" \
        "$MIDDLEWARE_VERSION" \
        "$MIDDLEWARE_BUILD_CONTEXT" \
        "$MIDDLEWARE_IMAGE_URI"
else
    echo "Skipping middleware image build/push because ENABLE_MIDDLEWARE=false"
fi

echo "Built and pushed ${LITELLM_IMAGE_URI}"
if [[ "$ENABLE_MIDDLEWARE" == "true" ]]; then
    echo "Built and pushed ${MIDDLEWARE_IMAGE_URI}"
fi
