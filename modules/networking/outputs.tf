output "VpcId" {
  description = "The ID of the VPC"
  value       = local.final_vpc_id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = local.creating_new_vpc ? local.new_private_subnet_ids : local.existing_private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = local.creating_new_vpc ? local.new_public_subnet_ids : local.existing_public_subnet_ids
}
