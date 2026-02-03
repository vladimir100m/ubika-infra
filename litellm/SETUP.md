# LiteLLM Setup Guide

## Configuration Files

### 1. litellm_config.yaml
Configuration file for LiteLLM with AWS Bedrock models:
- **Location**: `/Users/vlad/project/ubika-infra/litellm/litellm_config.yaml`
- **Master Key**: `sk-ubika-master-2026` (change in production!)
- **Models configured**:
  - `claude-3-sonnet` → AWS Bedrock Claude Sonnet
  - `claude-3-haiku` → AWS Bedrock Claude Haiku (cheaper)
  - `llama-3-8b` → AWS Bedrock Llama 3

### 2. Environment Variables
Set in `.env` file:
```bash
LITELLM_MASTER_KEY="sk-ubika-master-2026"
LITELLM_SALT_KEY="sk-ubika-salt-2026"
```

## Deployment Steps

### Step 1: Build and Push Docker Image
```bash
cd /Users/vlad/project/ubika-infra/litellm
./push-image.sh
```

This will:
- Build a custom LiteLLM image with your config baked in
- Build for ARM64 architecture (matches ECS Fargate ARM64)
- Push to ECR at: `703544859494.dkr.ecr.us-east-1.amazonaws.com/ubika-gateway:latest`

### Step 2: Deploy Updated ECS Stack
```bash
cd /Users/vlad/project/ubika-infra
uv run cdk deploy UbikaComputeStack
```

This updates the ECS task definition with:
- Bedrock IAM permissions
- Container command: `--config /app/config.yaml --port 4000 --detailed_debug`
- Environment variables for LiteLLM

### Step 3: Scale Up ECS Service
```bash
aws ecs update-service \
  --cluster UbikaComputeStack-GatewayCluster30039C24-vZisBhp59ufP \
  --service UbikaComputeStack-GatewayService20F4B805-ZiMSudLC6m2O \
  --desired-count 1 \
  --region us-east-1
```

### Step 4: Get Public IP and Test
```bash
# Wait for task to be RUNNING
aws ecs list-tasks \
  --cluster UbikaComputeStack-GatewayCluster30039C24-vZisBhp59ufP \
  --service-name UbikaComputeStack-GatewayService20F4B805-ZiMSudLC6m2O \
  --region us-east-1

# Get task ARN (replace <task-id> with actual ID from above)
TASK_ARN="arn:aws:ecs:us-east-1:703544859494:task/UbikaComputeStack-GatewayCluster30039C24-vZisBhp59ufP/<task-id>"

# Get public IP
PUBLIC_IP=$(aws ecs describe-tasks \
  --cluster UbikaComputeStack-GatewayCluster30039C24-vZisBhp59ufP \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text | xargs -I {} aws ec2 describe-network-interfaces \
  --network-interface-ids {} \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)

echo "Public IP: $PUBLIC_IP"

# Test health endpoint
curl http://$PUBLIC_IP:4000/health

# Test chat completion
curl -X POST "http://$PUBLIC_IP:4000/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-ubika-master-2026" \
  -d '{
    "model": "claude-3-haiku",
    "messages": [
      {
        "role": "user",
        "content": "Hello! What is your name?"
      }
    ]
  }'
```

## Architecture Changes

### IAM Permissions Added
1. **Task Execution Role** (already configured):
   - ECR pull permissions
   - CloudWatch Logs

2. **Task Role** (NEW):
   - `bedrock:InvokeModel`
   - `bedrock:InvokeModelWithResponseStream`

### Container Configuration
- **Platform**: ARM64 Linux (cost-effective)
- **Config file**: `/app/config.yaml` (baked into image)
- **Command**: `--config /app/config.yaml --port 4000 --detailed_debug`
- **Environment**: `LITELLM_MASTER_KEY`, `AWS_REGION_NAME`

## Cost Estimate
- **Fargate**: 0.25 vCPU ARM64 @ $0.03238/hr = ~$23/month
- **Bedrock**: Pay per use (Claude Haiku ~$0.25 per 1M input tokens)
- **ECR**: Within 500MB free tier
- **CloudWatch Logs**: Within 5GB free tier
- **Networking**: Internet Gateway (free)

**Total**: ~$30-40/month for infrastructure + Bedrock usage

## Security Notes
⚠️ **IMPORTANT**: Change the master key in production!
- Update `litellm_config.yaml` → `general_settings.master_key`
- Update `.env` → `LITELLM_MASTER_KEY`
- Rebuild and redeploy the image

## Available Models
After deployment, you can call these models via the proxy:
- `claude-3-sonnet` - Most capable Claude model
- `claude-3-haiku` - Fast and cost-effective
- `llama-3-8b` - Open source Llama model

## Next Steps
1. ✅ Configuration files created
2. ⏳ Build and push image: `./push-image.sh`
3. ⏳ Deploy stack: `uv run cdk deploy UbikaComputeStack`
4. ⏳ Scale service to 1 task
5. ⏳ Test API endpoints
