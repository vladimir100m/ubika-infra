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

  default_tags {
    tags = {
      project     = "ubika-infra"
      managed_by  = "terraform"
      environment = var.environment
    }
  }
}

