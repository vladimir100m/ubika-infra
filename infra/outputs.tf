
output "VpcId" {
  value       = module.base.VpcId
  description = "The ID of the VPC"
}

output "private_subnet_ids" {
  value       = module.base.private_subnet_ids
  description = "List of IDs of private subnets"
}

output "public_subnet_ids" {
  value       = module.base.public_subnet_ids
  description = "List of IDs of public subnets"
}
