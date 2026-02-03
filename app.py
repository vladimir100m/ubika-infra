#!/usr/bin/env python3
import os
import aws_cdk as cdk
from dotenv import load_dotenv

from stacks.compute_stack import ComputeStack
from stacks.database_stack import DatabaseStack
from stacks.gateway_network_security_stack import GatewayNetworkSecurityStack
from stacks.network_stack import NetworkStack

# Load environment variables from .env file
load_dotenv()


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


max_azs = _to_int(app.node.try_get_context("max_azs"), int(os.getenv("MAX_AZS", "1")))
nat_gateways = _to_int(app.node.try_get_context("nat_gateways"), int(os.getenv("NAT_GATEWAYS", "0")))
enable_public_subnets = _to_bool(
    app.node.try_get_context("enable_public_subnets"), 
    _to_bool(os.getenv("ENABLE_PUBLIC_SUBNETS"), True)
)
enable_private_egress_subnets = _to_bool(
    app.node.try_get_context("enable_private_egress_subnets"),
    _to_bool(os.getenv("ENABLE_PRIVATE_EGRESS_SUBNETS"), False)
)
enable_isolated_subnets = _to_bool(
    app.node.try_get_context("enable_isolated_subnets"),
    _to_bool(os.getenv("ENABLE_ISOLATED_SUBNETS"), True)
)
enable_flow_logs = _to_bool(
    app.node.try_get_context("enable_flow_logs"),
    _to_bool(os.getenv("ENABLE_FLOW_LOGS"), False)
)

# ALB configuration
enable_alb = _to_bool(
    app.node.try_get_context("enable_alb"),
    _to_bool(os.getenv("ENABLE_ALB"), True)
)
alb_target_port = _to_int(app.node.try_get_context("alb_target_port"), int(os.getenv("ALB_TARGET_PORT", "4000")))

# ALB configuration
enable_alb = _to_bool(
    app.node.try_get_context("enable_alb"),
    _to_bool(os.getenv("ENABLE_ALB"), False)
)
alb_target_port = _to_int(app.node.try_get_context("alb_target_port"), int(os.getenv("ALB_TARGET_PORT", "4000")))

# ECS configuration
ecs_subnet_group_name = app.node.try_get_context("ecs_subnet_group_name") or os.getenv("ECS_SUBNET_GROUP_NAME", "Public")
ecs_container_port = _to_int(app.node.try_get_context("ecs_container_port"), int(os.getenv("ECS_CONTAINER_PORT", "4000")))
ecs_desired_count = _to_int(app.node.try_get_context("ecs_desired_count"), int(os.getenv("ECS_DESIRED_COUNT", "0")))
ecs_cpu = _to_int(app.node.try_get_context("ecs_cpu"), int(os.getenv("ECS_CPU", "256")))
ecs_memory_mib = _to_int(app.node.try_get_context("ecs_memory_mib"), int(os.getenv("ECS_MEMORY_MIB", "512")))
litellm_master_key = app.node.try_get_context("litellm_master_key") or os.getenv("LITELLM_MASTER_KEY", "sk-ubika-master-2026")

# Other configuration
enable_interface_endpoints = _to_bool(
    app.node.try_get_context("enable_interface_endpoints"),
    _to_bool(os.getenv("ENABLE_INTERFACE_ENDPOINTS"), False)
)

# ECR configuration
ecr_repository_name = app.node.try_get_context("ecr_repository_name") or os.getenv("ECR_REPOSITORY_NAME", "ubika-gateway")
account_id = app.node.try_get_context("account") or os.getenv("ACCOUNT_ID", "703544859494")
region = app.node.try_get_context("region") or os.getenv("AWS_REGION", "us-east-1")

# Construct ECR repository URI dynamically
ecr_repository_uri = f"{account_id}.dkr.ecr.{region}.amazonaws.com/{ecr_repository_name}"

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

# Create gateway security stack
gateway_stack = GatewayNetworkSecurityStack(
    app,
    "UbikaGatewayNetworkSecurityStack",
    description="Security layer for LiteLLM gateway - allows public access",
    vpc=network_stack.vpc,
    gateway_target_port=ecs_container_port,
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

# Create database stack
database_stack = DatabaseStack(
    app,
    "UbikaDatabaseStack",
    description="PostgreSQL database for LiteLLM proxy",
    vpc=network_stack.vpc,
    database_name="litellm",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

compute_stack = ComputeStack(
    app,
    "UbikaComputeStack",
    description="ECS Fargate compute layer for gateway services",
    vpc=network_stack.vpc,
    ecr_repository_uri=ecr_repository_uri,
    service_security_group=gateway_stack.gateway_security_group,
    db_instance=database_stack.db_instance,
    db_credentials_secret=database_stack.db_instance.secret,
    db_security_group=database_stack.db_security_group,
    ecs_subnet_group_name=ecs_subnet_group_name,
    container_port=ecs_container_port,
    desired_count=ecs_desired_count,
    cpu=ecs_cpu,
    memory_mib=ecs_memory_mib,
    litellm_master_key=litellm_master_key,
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()
