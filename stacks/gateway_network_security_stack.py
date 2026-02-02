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
    Networking and security layer for Scenario 4 (Private VPC Only).

    Creates:
    - Private Route53 hosted zone and DNS record
    - Internal ALB with HTTPS listener
    - Security groups for ALB and gateway workloads
    - VPC endpoints for private access to AWS services
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        hosted_zone_name: str,
        record_name: str,
        allowed_cidr_blocks: Optional[List[str]] = None,
        certificate_arn: Optional[str] = None,
        enable_https: bool = False,
        enable_alb: bool = False,
        create_private_hosted_zone: bool = True,
        enable_interface_endpoints: bool = False,
        alb_subnet_group_name: str = "Isolated",
        gateway_target_port: int = 4000,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        if enable_alb and create_private_hosted_zone and (not hosted_zone_name or not record_name):
            raise ValueError("hosted_zone_name and record_name are required")

        if enable_https and not enable_alb:
            raise ValueError("enable_alb must be True when enable_https=True")

        if enable_https and not certificate_arn:
            raise ValueError("certificate_arn is required when enable_https=True")

        allowed_cidrs = allowed_cidr_blocks or [vpc.vpc_cidr_block]

        private_zone = None
        if enable_alb and create_private_hosted_zone:
            private_zone = route53.PrivateHostedZone(
                self,
                "GatewayPrivateZone",
                zone_name=hosted_zone_name,
                vpc=vpc,
            )

        certificate = None
        if enable_https:
            certificate = acm.Certificate.from_certificate_arn(
                self,
                "GatewayCertificate",
                certificate_arn,
            )

        gateway_security_group = ec2.SecurityGroup(
            self,
            "GatewayServiceSecurityGroup",
            vpc=vpc,
            description="Gateway service security group",
            allow_all_outbound=True,
        )
        if enable_alb:
            alb_security_group = ec2.SecurityGroup(
                self,
                "GatewayAlbSecurityGroup",
                vpc=vpc,
                description="ALB security group for private gateway",
                allow_all_outbound=True,
            )

            alb_listener_port = 443 if enable_https else 80
            for cidr in allowed_cidrs:
                alb_security_group.add_ingress_rule(
                    ec2.Peer.ipv4(cidr),
                    ec2.Port.tcp(alb_listener_port),
                    "Allow ALB access from private/corporate networks",
                )

            gateway_security_group.add_ingress_rule(
                alb_security_group,
                ec2.Port.tcp(gateway_target_port),
                "Allow traffic from ALB",
            )

            alb = elbv2.ApplicationLoadBalancer(
                self,
                "GatewayAlb",
                vpc=vpc,
                internet_facing=False,
                security_group=alb_security_group,
                vpc_subnets=ec2.SubnetSelection(
                    subnet_group_name=alb_subnet_group_name
                ),
            )

            if enable_https:
                alb.add_listener(
                    "HttpsListener",
                    port=443,
                    certificates=[certificate],
                    ssl_policy=elbv2.SslPolicy.RECOMMENDED,
                    default_action=elbv2.ListenerAction.fixed_response(
                        status_code=503,
                        message_body="Gateway not deployed yet",
                        content_type="text/plain",
                    ),
                )
            else:
                alb.add_listener(
                    "HttpListener",
                    port=80,
                    default_action=elbv2.ListenerAction.fixed_response(
                        status_code=503,
                        message_body="Gateway not deployed yet",
                        content_type="text/plain",
                    ),
                )

            if private_zone is not None:
                route53.ARecord(
                    self,
                    "GatewayDnsRecord",
                    zone=private_zone,
                    record_name=record_name,
                    target=route53.RecordTarget.from_alias(
                        targets.LoadBalancerTarget(alb)
                    ),
                )
        else:
            for cidr in allowed_cidrs:
                gateway_security_group.add_ingress_rule(
                    ec2.Peer.ipv4(cidr),
                    ec2.Port.tcp(gateway_target_port),
                    "Allow direct access to gateway service",
                )

        vpc.add_gateway_endpoint(
            "S3GatewayEndpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
        )

        if enable_interface_endpoints:
            endpoint_security_group = ec2.SecurityGroup(
                self,
                "VpcEndpointSecurityGroup",
                vpc=vpc,
                description="Security group for interface VPC endpoints",
                allow_all_outbound=True,
            )
            endpoint_security_group.add_ingress_rule(
                ec2.Peer.ipv4(vpc.vpc_cidr_block),
                ec2.Port.tcp(443),
                "Allow VPC access to endpoints",
            )

            interface_services = [
                ec2.InterfaceVpcEndpointAwsService.ECR,
                ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
                ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
                ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
                ec2.InterfaceVpcEndpointAwsService.STS,
                ec2.InterfaceVpcEndpointAwsService.KMS,
                ec2.InterfaceVpcEndpointAwsService.BEDROCK,
                ec2.InterfaceVpcEndpointAwsService.BEDROCK_RUNTIME,
            ]

            for service in interface_services:
                vpc.add_interface_endpoint(
                    f"{service.short_name.capitalize()}Endpoint",
                    service=service,
                    security_groups=[endpoint_security_group],
                    private_dns_enabled=True,
                    subnets=ec2.SubnetSelection(
                        subnet_group_name=alb_subnet_group_name
                    ),
                )

        if enable_alb:
            CfnOutput(
                self,
                "GatewayAlbDnsName",
                value=alb.load_balancer_dns_name,
                description="Internal ALB DNS name",
            )

            if private_zone is not None:
                scheme = "https" if enable_https else "http"
                CfnOutput(
                    self,
                    "GatewayPrivateUrl",
                    value=f"{scheme}://{record_name}.{hosted_zone_name}",
                    description="Private gateway URL",
                )

            CfnOutput(
                self,
                "GatewayAlbSecurityGroupId",
                value=alb_security_group.security_group_id,
                description="ALB security group ID",
            )

        CfnOutput(
            self,
            "GatewayServiceSecurityGroupId",
            value=gateway_security_group.security_group_id,
            description="Gateway service security group ID",
        )

        if enable_alb and private_zone is not None:
            CfnOutput(
                self,
                "PrivateHostedZoneId",
                value=private_zone.hosted_zone_id,
                description="Route53 private hosted zone ID",
            )
