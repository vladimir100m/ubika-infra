#!/bin/bash

# Push LiteLLM image to ECR
# Prerequisites:
# - AWS CLI configured with credentials
# - Docker installed and running
# - jq installed (for parsing JSON)

set -e

GHCR_IMAGE="ghcr.io/berriai/litellm:main-latest"
ECR_REPO_NAME="ubika-gateway"

echo "📦 Fetching ECR repository URI from CloudFormation..."

# Get stack outputs
STACK_NAME="UbikaComputeStack"
ECR_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text)

if [ -z "$ECR_REPO_URI" ]; then
  echo "❌ Error: Could not find ECR repository URI. Make sure the stack is deployed."
  exit 1
fi

echo "✅ ECR Repository URI: $ECR_REPO_URI"

# Get AWS account ID and region
AWS_ACCOUNT=$(echo "$ECR_REPO_URI" | cut -d'.' -f1)
AWS_REGION=$(echo "$ECR_REPO_URI" | cut -d'.' -f4)

echo "📍 AWS Account: $AWS_ACCOUNT, Region: $AWS_REGION"

echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "⬇️  Pulling image from GHCR..."
docker pull "$GHCR_IMAGE"

echo "🏷️  Tagging image for ECR..."
docker tag "$GHCR_IMAGE" "$ECR_REPO_URI:main-latest"
docker tag "$GHCR_IMAGE" "$ECR_REPO_URI:latest"

echo "⬆️  Pushing image to ECR..."
docker push "$ECR_REPO_URI:main-latest"
docker push "$ECR_REPO_URI:latest"

echo "✅ Successfully pushed LiteLLM image to ECR!"
echo "   Repository: $ECR_REPO_URI"
echo "   Tags: main-latest, latest"
