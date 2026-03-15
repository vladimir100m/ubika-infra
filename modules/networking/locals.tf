locals {
  nat_gateway_count = var.disable_outbound_network_access ? 0 : 1

  creating_new_vpc = length(trimspace(var.vpc_id)) == 0
  final_vpc_id     = local.creating_new_vpc ? aws_vpc.new[0].id : data.aws_vpc.existing[0].id
}

locals {
  creating_new_vpc = var.vpc_id == ""
  nat_gateway_count = var.disable_outbound_network_access || !var.enable_nat_gateway ? 0 : (var.single_nat_gateway ? 1 : 2)
}

data "aws_subnets" "public_ip_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_route_table" "subnet_route_tables" {
  for_each  = toset(data.aws_subnets.public_ip_subnets.ids)
  subnet_id = each.value
}

data "aws_subnets" "private_ip_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

data "aws_route_table" "private_subnet_route_tables" {
  for_each  = toset(data.aws_subnets.private_ip_subnets.ids)
  subnet_id = each.value
}

locals {
  new_private_subnet_ids = flatten([for s in aws_subnet.private : s.id])
  new_public_subnet_ids  = flatten([for s in aws_subnet.public : s.id])

  existing_public_subnet_ids = [
    for subnet_id, rt in data.aws_route_table.subnet_route_tables : subnet_id
    if length([
      for route in rt.routes : route
      if route.gateway_id != null &&
      can(regex("^igw-", route.gateway_id)) &&
      route.cidr_block == "0.0.0.0/0"
    ]) > 0
  ]

  existing_private_subnet_ids = [
    for subnet_id, rt in data.aws_route_table.private_subnet_route_tables : subnet_id
    if length([
      for route in rt.routes : route
      if route.gateway_id != null &&
      can(regex("^igw-", route.gateway_id)) &&
      route.cidr_block == "0.0.0.0/0"
    ]) == 0
  ]

  chosen_subnet_ids = local.creating_new_vpc ? local.new_private_subnet_ids : local.existing_private_subnet_ids
}

locals {
  create_endpoints = (local.creating_new_vpc || var.create_vpc_endpoints_in_existing_vpc)
}

data "aws_route_tables" "existing_vpc_all" {
  count = local.creating_new_vpc ? 0 : 1
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

locals {
  s3_gateway_route_table_ids = local.creating_new_vpc ? [aws_route_table.public[0].id, local.private_route_table.id] : data.aws_route_tables.existing_vpc_all[0].ids
  private_route_table        = local.creating_new_vpc ? (local.nat_gateway_count == 1 ? aws_route_table.private_with_nat[0] : aws_route_table.private_isolated[0]) : (null)
}

data "aws_vpc_endpoint_service" "bedrock_agent" {
  service_name = "com.amazonaws.${data.aws_region.current.name}.bedrock-agent"
}

data "aws_subnet" "chosen_subnets" {
  count = length(local.chosen_subnet_ids)
  id    = local.chosen_subnet_ids[count.index]
}

locals {
  subnet_az_map = {
    for idx, s in data.aws_subnet.chosen_subnets :
    s.id => s.availability_zone
  }
}

locals {
  bedrock_agent_compatible_subnets = [
    for subnet_id in local.chosen_subnet_ids : subnet_id
    if contains(data.aws_vpc_endpoint_service.bedrock_agent.availability_zones, local.subnet_az_map[subnet_id])
  ]
}
