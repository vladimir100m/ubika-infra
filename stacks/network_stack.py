from aws_cdk import (
    CfnOutput,
    Stack,
    Tags,
)
from constructs import Construct
import aws_cdk.aws_ec2 as ec2


class NetworkStack(Stack):
    """
    Well-Architected VPC Stack (configurable for free-tier MVP).

    Defaults are cost-optimized:
    - Single AZ
    - No NAT Gateways
    - Isolated subnets only
    - Flow logs disabled
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        max_azs: int = 1,
        nat_gateways: int = 0,
        enable_public_subnets: bool = False,
        enable_private_egress_subnets: bool = False,
        enable_isolated_subnets: bool = True,
        enable_flow_logs: bool = False,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        subnet_configuration = []
        if enable_public_subnets:
            subnet_configuration.append(
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            )

        if enable_private_egress_subnets:
            subnet_configuration.append(
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                )
            )

        if enable_isolated_subnets or not subnet_configuration:
            subnet_configuration.append(
                ec2.SubnetConfiguration(
                    name="Isolated",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                )
            )

        self.vpc = ec2.Vpc(
            self,
            "UbikaVPC",
            vpc_name="ubika-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=max_azs,
            nat_gateways=nat_gateways,
            subnet_configuration=subnet_configuration,
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        if enable_flow_logs:
            ec2.FlowLog(
                self,
                "VPCFlowLog",
                resource_type=ec2.FlowLogResourceType.from_vpc(self.vpc),
                traffic_type=ec2.FlowLogTrafficType.ALL,
            )

        Tags.of(self.vpc).add("Environment", "mvp")
        Tags.of(self.vpc).add("Project", "Ubika")
        Tags.of(self.vpc).add("ManagedBy", "CDK")

        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID",
            export_name="UbikaVPCId",
        )

        CfnOutput(
            self,
            "VPCCidr",
            value=self.vpc.vpc_cidr_block,
            description="VPC CIDR Block",
        )

        if self.vpc.public_subnets:
            CfnOutput(
                self,
                "PublicSubnets",
                value=",".join(
                    [subnet.subnet_id for subnet in self.vpc.public_subnets]
                ),
                description="Public Subnet IDs",
            )

        if self.vpc.private_subnets:
            CfnOutput(
                self,
                "PrivateSubnets",
                value=",".join(
                    [subnet.subnet_id for subnet in self.vpc.private_subnets]
                ),
                description="Private Subnet IDs",
            )

        if self.vpc.isolated_subnets:
            CfnOutput(
                self,
                "IsolatedSubnets",
                value=",".join(
                    [subnet.subnet_id for subnet in self.vpc.isolated_subnets]
                ),
                description="Isolated Subnet IDs",
            )
