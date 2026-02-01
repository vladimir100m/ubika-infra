# Ubika Infrastructure - AWS CDK

Well-Architected VPC infrastructure deployed using AWS CDK with Python.

## Architecture

This infrastructure includes:

- **VPC** (`10.0.0.0/16`)
  - 3 Availability Zones for high availability
  - DNS hostnames and DNS support enabled
  - VPC Flow Logs for security monitoring

- **Public Subnets** (3 subnets, one per AZ)
  - CIDR: `/24` per subnet (256 IPs each)
  - Internet Gateway for outbound/inbound internet access
  - For resources like Load Balancers, Bastion hosts

- **Private Subnets** (3 subnets, one per AZ)
  - CIDR: `/24` per subnet (256 IPs each)
  - NAT Gateways (one per AZ) for outbound internet access
  - For application servers, EC2 instances

- **Isolated Subnets** (3 subnets, one per AZ)
  - CIDR: `/24` per subnet (256 IPs each)
  - No internet access
  - For databases and sensitive data

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate credentials
- Node.js 14.x or later (for AWS CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Setup

1. **Create a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On macOS/Linux
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure AWS credentials** (if not already done):
   ```bash
   aws configure
   ```

4. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap aws://ACCOUNT-ID/REGION
   ```

## Deployment

1. **Synthesize the CloudFormation template**:
   ```bash
   cdk synth
   ```

2. **Deploy the infrastructure**:
   ```bash
   cdk deploy
   ```

3. **View the outputs**:
   After deployment, the stack will output:
   - VPC ID
   - VPC CIDR Block
   - Public Subnet IDs
   - Private Subnet IDs
   - Isolated Subnet IDs

## Useful Commands

- `cdk ls` - List all stacks
- `cdk synth` - Synthesize CloudFormation template
- `cdk deploy` - Deploy the stack
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove the stack

## Cost Considerations

This infrastructure will incur costs for:
- NAT Gateways (~$0.045/hour per NAT Gateway = ~$97/month for 3)
- Data transfer through NAT Gateways
- VPC Flow Logs storage (CloudWatch Logs or S3)

## Security Features

- VPC Flow Logs enabled for network monitoring
- Multi-AZ deployment for high availability
- Isolated subnets for databases (no internet access)
- Separate NAT Gateways per AZ for fault tolerance

## Next Steps

You can extend this infrastructure by:
- Adding Application Load Balancers in public subnets
- Deploying EC2 instances or ECS/EKS clusters in private subnets
- Adding RDS databases in isolated subnets
- Implementing VPC endpoints for AWS services
- Adding Security Groups and NACLs
