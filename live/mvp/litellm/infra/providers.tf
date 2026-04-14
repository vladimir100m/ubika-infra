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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Auth: use AWS_PROFILE (see Makefile init-mvp / apply-mvp).

  default_tags {
    tags = {
      project     = "ubika-infra"
      managed_by  = "terraform"
      environment = var.environment
    }
  }
}
