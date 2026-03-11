###############################################################################
# modules/ecs-cluster
#
# Provisions a shared ECS Fargate cluster.
# - Container Insights enabled
# - FARGATE and FARGATE_SPOT capacity providers
#
# Reusable for: any environment that runs Fargate workloads.
###############################################################################

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.name}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}
