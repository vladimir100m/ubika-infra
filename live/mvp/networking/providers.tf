terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Auth: use AWS_PROFILE (see Makefile init-mvp / apply-mvp). SSO lives in ~/.aws/config;
  # AWS_SDK_LOAD_CONFIG=1 ensures the SDK loads it the same way as the AWS CLI.

  default_tags {
    tags = {
      project     = "ubika-infra"
      managed_by  = "terraform"
      environment = var.environment
    }
  }
}
