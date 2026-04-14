module "networking" {
  source = "../../../modules/networking"

  name                                 = var.name
  vpc_id                               = var.vpc_id
  create_vpc_endpoints_in_existing_vpc = var.create_vpc_endpoints_in_existing_vpc
  disable_outbound_network_access      = var.disable_outbound_network_access

  enable_nat_gateway             = false
  single_nat_gateway             = true
  enable_interface_vpc_endpoints = false
  enable_s3_gateway_endpoint     = true
  enable_vpc_flow_logs           = false
}
