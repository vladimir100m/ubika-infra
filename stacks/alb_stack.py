from typing import List, Optional

from aws_cdk import (
    CfnOutput,
    Duration,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_elasticloadbalancingv2 as elbv2


class AlbStack(Stack):
    """
    Application Load Balancer stack for external access to LiteLLM gateway.

    Creates:
    - ALB in public subnets with HTTP listener
    - Security group allowing inbound HTTP/HTTPS (0.0.0.0/0)
    - Target group for ECS tasks on port 4000
    - Outputs: ALB DNS name, target group ARN, security group ID
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        alb_subnet_group_name: str = "Public",
        target_port: int = 4000,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get public subnets
        public_subnets = vpc.select_subnets(
            subnet_group_name=alb_subnet_group_name
        ).subnets

        if not public_subnets:
            raise ValueError(
                f"No {alb_subnet_group_name} subnets found in VPC. "
                "Ensure enable_public_subnets=true in network configuration."
            )

        # ALB Security Group - Allow HTTP from anywhere
        self.alb_security_group = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=vpc,
            description="ALB security group for LiteLLM gateway",
            allow_all_outbound=True,
        )

        # Allow HTTP and HTTPS from anywhere
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from anywhere",
        )

        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from anywhere",
        )

        # Create ALB
        self.alb = elbv2.ApplicationLoadBalancer(
            self,
            "LiteLLMAlb",
            vpc=vpc,
            internet_facing=True,
            load_balancer_name="litellm-alb",
            security_group=self.alb_security_group,
        )

        # Create target group for ECS tasks
        self.target_group = elbv2.ApplicationTargetGroup(
            self,
            "LiteLLMTargetGroup",
            vpc=vpc,
            port=target_port,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            target_group_name="litellm-targets",
            health_check=elbv2.HealthCheck(
                path="/health",
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )

        # HTTP listener routing to target group
        self.alb.add_listener(
            "HttpListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group],
        )

        # Outputs
        CfnOutput(
            self,
            "AlbDnsName",
            value=self.alb.load_balancer_dns_name,
            description="ALB DNS name for accessing LiteLLM gateway",
            export_name="AlbDnsName",
        )

        CfnOutput(
            self,
            "AlbArn",
            value=self.alb.load_balancer_arn,
            description="ALB ARN",
            export_name="AlbArn",
        )

        CfnOutput(
            self,
            "TargetGroupArn",
            value=self.target_group.target_group_arn,
            description="Target group ARN for ECS tasks",
            export_name="TargetGroupArn",
        )

        CfnOutput(
            self,
            "AlbSecurityGroupId",
            value=self.alb_security_group.security_group_id,
            description="ALB security group ID",
            export_name="AlbSecurityGroupId",
        )
