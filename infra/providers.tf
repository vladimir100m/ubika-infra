data "aws_caller_identity" "current" {}
data "aws_eks_cluster_auth" "cluster" {
terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
    cluster_ca_certificate = local.platform == "EKS" ? base64decode(module.eks_cluster[0].cluster_ca) : ""
    token = local.platform == "EKS" ? data.aws_eks_cluster_auth.cluster[0].token : ""
  }
}
