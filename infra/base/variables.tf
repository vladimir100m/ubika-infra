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
