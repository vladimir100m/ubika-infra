from typing import List, Optional

from aws_cdk import (
    CfnOutput,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_certificatemanager as acm
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_elasticloadbalancingv2 as elbv2
import aws_cdk.aws_route53 as route53
import aws_cdk.aws_route53_targets as targets


class GatewayNetworkSecurityStack(Stack):
    """
    Networking and security layer for LiteLLM gateway.

    Creates:
    - Security group for ECS tasks (public access optional)
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        gateway_target_port: int = 4000,
        allow_public_access: bool = False,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Gateway service security group
        gateway_security_group = ec2.SecurityGroup(
            self,
            "GatewayServiceSecurityGroup",
            vpc=vpc,
            description="Gateway service security group",
            allow_all_outbound=True,
        )
        self.gateway_security_group = gateway_security_group

        # Optional public access on gateway port (typically disabled when using ALB)
        if allow_public_access:
            gateway_security_group.add_ingress_rule(
                ec2.Peer.any_ipv4(),
                ec2.Port.tcp(gateway_target_port),
                "Allow public access to gateway service",
            )

        # VPC S3 Gateway Endpoint
        vpc.add_gateway_endpoint(
            "S3GatewayEndpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
        )

        # Outputs
        CfnOutput(
            self,
            "GatewayServiceSecurityGroupId",
            value=gateway_security_group.security_group_id,
            description="Gateway service security group ID",
            export_name="GatewaySecurityGroupId",
        )
