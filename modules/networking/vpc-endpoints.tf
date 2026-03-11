data "aws_region" "current" {}

resource "aws_security_group" "vpc_endpoints_sg" {
  count       = local.create_endpoints ? 1 : 0
  name        = "${var.name}-vpc-endpoints-sg"
  description = "Security group for Interface VPC Endpoints"
  vpc_id      = local.final_vpc_id
  ingress {
    description = "allow inbound access from within the vpc"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.creating_new_vpc ? aws_vpc.new[0].cidr_block : data.aws_vpc.existing[0].cidr_block]
  }
  egress {
    description = "allow all outbound access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count             = local.create_endpoints ? 1 : 0
  vpc_id            = local.final_vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.s3_gateway_route_table_ids
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count               = local.create_endpoints ? 1 : 0
  vpc_id              = local.final_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
  subnet_ids          = local.chosen_subnet_ids
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr" {
  count               = local.create_endpoints ? 1 : 0
  vpc_id              = local.final_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
  subnet_ids          = local.chosen_subnet_ids
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_docker" {
  count               = local.create_endpoints ? 1 : 0
  vpc_id              = local.final_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
  subnet_ids          = local.chosen_subnet_ids
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  count               = local.create_endpoints ? 1 : 0
  vpc_id              = local.final_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
  subnet_ids          = local.chosen_subnet_ids
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sts" {
  count               = local.create_endpoints ? 1 : 0
  vpc_id              = local.final_vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
  subnet_ids          = local.chosen_subnet_ids
  private_dns_enabled = true
}
