#!/bin/bash

# Push LiteLLM image to ECR
# Prerequisites:
# - AWS CLI configured with credentials
# - Docker installed and running
# - jq installed (for parsing JSON)

set -e

GHCR_IMAGE="ghcr.io/berriai/litellm:main-latest"
ECR_REPO_NAME="ubika-gateway"

echo "📦 Setting up ECR repository URI..."

# Get AWS account ID and region from environment or defaults
AWS_ACCOUNT="${AWS_ACCOUNT_ID:-703544859494}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO_URI="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "✅ ECR Repository URI: $ECR_REPO_URI"

echo "📍 AWS Account: $AWS_ACCOUNT, Region: $AWS_REGION"

echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "🏗️  Building custom LiteLLM image with config..."
docker build --platform linux/arm64 -t "$ECR_REPO_URI:latest" .

echo "⬆️  Pushing image to ECR..."
docker push "$ECR_REPO_URI:latest"

echo "✅ Successfully pushed LiteLLM image to ECR!"
echo "   Repository: $ECR_REPO_URI"
echo "   Tag: latest"
echo ""
echo "📝 Next steps:"
echo "   1. Deploy the updated ECS stack: cd .. && uv run cdk deploy UbikaComputeStack"
echo "   2. Scale up the service: aws ecs update-service --cluster <cluster-name> --service <service-name> --desired-count 1 --region us-east-1"
