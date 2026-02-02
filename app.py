#!/usr/bin/env python3
import aws_cdk as cdk

from stacks.compute_stack import ComputeStack
from stacks.gateway_network_security_stack import GatewayNetworkSecurityStack
from stacks.network_stack import NetworkStack


app = cdk.App()


def _to_bool(value, default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y"}
    return bool(value)


def _to_int(value, default=0):
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


max_azs = _to_int(app.node.try_get_context("max_azs"), 1)
nat_gateways = _to_int(app.node.try_get_context("nat_gateways"), 0)
enable_public_subnets = _to_bool(
    app.node.try_get_context("enable_public_subnets"), False
)
enable_private_egress_subnets = _to_bool(
    app.node.try_get_context("enable_private_egress_subnets"), False
)
enable_isolated_subnets = _to_bool(
    app.node.try_get_context("enable_isolated_subnets"), True
)
enable_flow_logs = _to_bool(app.node.try_get_context("enable_flow_logs"), False)

network_stack = NetworkStack(
    app,
    "UbikaNetworkStack",
    description="Well-Architected VPC Infrastructure",
    max_azs=max_azs,
    nat_gateways=nat_gateways,
    enable_public_subnets=enable_public_subnets,
    enable_private_egress_subnets=enable_private_egress_subnets,
    enable_isolated_subnets=enable_isolated_subnets,
    enable_flow_logs=enable_flow_logs,
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

hosted_zone_name = app.node.try_get_context("hosted_zone_name") or "example.internal"
record_name = app.node.try_get_context("record_name") or "genai"
certificate_arn = app.node.try_get_context("certificate_arn")
enable_https = _to_bool(app.node.try_get_context("enable_https"), False)
create_private_hosted_zone = _to_bool(
    app.node.try_get_context("create_private_hosted_zone"), False
)
enable_interface_endpoints = _to_bool(
    app.node.try_get_context("enable_interface_endpoints"), False
)
alb_subnet_group_name = app.node.try_get_context("alb_subnet_group_name") or (
    "Private" if enable_private_egress_subnets else "Isolated"
)

ecs_subnet_group_name = app.node.try_get_context("ecs_subnet_group_name") or (
    "Private" if enable_private_egress_subnets else "Isolated"
)
ecs_container_port = _to_int(app.node.try_get_context("ecs_container_port"), 4000)
ecs_desired_count = _to_int(app.node.try_get_context("ecs_desired_count"), 0)
ecs_cpu = _to_int(app.node.try_get_context("ecs_cpu"), 256)
ecs_memory_mib = _to_int(app.node.try_get_context("ecs_memory_mib"), 512)
ecr_repository_name = (
    app.node.try_get_context("ecr_repository_name") or "ubika-gateway"
)

allowed_cidrs_context = app.node.try_get_context("allowed_cidrs")
if isinstance(allowed_cidrs_context, str):
    allowed_cidr_blocks = [
        cidr.strip() for cidr in allowed_cidrs_context.split(",") if cidr.strip()
    ]
elif isinstance(allowed_cidrs_context, list):
    allowed_cidr_blocks = [cidr for cidr in allowed_cidrs_context if cidr]
else:
    allowed_cidr_blocks = [network_stack.vpc.vpc_cidr_block]

gateway_stack = GatewayNetworkSecurityStack(
    app,
    "UbikaGatewayNetworkSecurityStack",
    description="Private VPC-only networking and security layer for LLM gateway",
    vpc=network_stack.vpc,
    hosted_zone_name=hosted_zone_name,
    record_name=record_name,
    allowed_cidr_blocks=allowed_cidr_blocks,
    certificate_arn=certificate_arn,
    enable_https=enable_https,
    create_private_hosted_zone=create_private_hosted_zone,
    enable_interface_endpoints=enable_interface_endpoints,
    alb_subnet_group_name=alb_subnet_group_name,
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

ComputeStack(
    app,
    "UbikaComputeStack",
    description="ECS Fargate compute layer for gateway services",
    vpc=network_stack.vpc,
    service_security_group=gateway_stack.gateway_security_group,
    ecs_subnet_group_name=ecs_subnet_group_name,
    container_port=ecs_container_port,
    desired_count=ecs_desired_count,
    cpu=ecs_cpu,
    memory_mib=ecs_memory_mib,
    repository_name=ecr_repository_name,
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()
