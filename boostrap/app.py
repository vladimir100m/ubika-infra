#!/usr/bin/env python3
import os
import aws_cdk as cdk
from dotenv import load_dotenv

from stacks.s3_bucket_stack import S3BucketStack

# Load environment variables from .env file
load_dotenv()


app = cdk.App()

# Get AWS account and region from context or environment
account_id = app.node.try_get_context("account") or os.getenv("ACCOUNT_ID")
region = app.node.try_get_context("region") or os.getenv("AWS_REGION", "us-east-1")
if not account_id:
    raise ValueError("ACCOUNT_ID must be set via context or environment")

# Create S3 bucket stack
s3_bucket_stack = S3BucketStack(
    app,
    "TerraformUbikaBucketStack",
    description="S3 bucket for terraform state",
    bucket_name=f"terraform-ubika-{account_id}",
    env=cdk.Environment(
        account=account_id,
        region=region,
    ),
)

app.synth()