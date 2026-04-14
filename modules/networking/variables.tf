variable "name" {
  description = "Standard name to be used as prefix on all resources."
  type        = string
}

variable "vpc_id" {
  description = "ID of an existing VPC to use. If not provided, a new VPC will be created."
  type        = string
  default     = ""
}

variable "disable_outbound_network_access" {
  description = "Whether to disable outbound network access"
  type        = bool
}

variable "create_vpc_endpoints_in_existing_vpc" {
  type        = bool
  description = "If using an existing VPC, set this to true to also create interface/gateway endpoints within it."
}

variable "hostedZoneName" {
  description = "Hosted zone name"
  type        = string
  default     = ""
}

variable "publicLoadBalancer" {
  description = "Whether the load balancer is public or private"
  type        = bool
  default     = true
}

variable "create_private_hosted_zone_in_existing_vpc" {
  description = "In the case publicLoadBalancer=false (meaning we need a private hosted zone), and an vpc_id is provided, decides whether we create a private hosted zone, or assume one already exists and import it"
  type        = bool
  default     = false
}

variable "use_route53" {
  description = "Whether to use Route53 for DNS resources in the base module"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "If true, a single NAT Gateway will be shared across all private subnets. If false, one will be created per AZ."
  type        = bool
  default     = true
}

variable "enable_interface_vpc_endpoints" {
  description = "Create Interface VPC Endpoints (Secrets Manager, ECR, CloudWatch Logs, STS). Disable for minimal-cost MVP when not needed."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the S3 Gateway VPC Endpoint (no hourly charge). Often kept enabled for private subnet S3 access without NAT."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Publish VPC flow logs to CloudWatch Logs. Disable for MVP to avoid log storage cost."
  type        = bool
  default     = true
}