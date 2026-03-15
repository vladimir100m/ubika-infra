module "networking" {
  source = "../../../modules/networking"

  name                                 = var.name
  vpc_id                               = var.vpc_id
  create_vpc_endpoints_in_existing_vpc = var.create_vpc_endpoints_in_existing_vpc
  disable_outbound_network_access      = var.disable_outbound_network_access

  enable_nat_gateway     = true
  single_nat_gateway     = true
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [module.networking.VpcId]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [module.networking.VpcId]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}
