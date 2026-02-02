from typing import Optional

from aws_cdk import (
    CfnOutput,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_ecr as ecr
import aws_cdk.aws_ecs as ecs
import aws_cdk.aws_logs as logs


class ComputeStack(Stack):
    """
    ECS Fargate compute stack with an ECR repository.

    Creates:
    - ECR repository for gateway images
    - ECS cluster
    - Fargate task definition + service
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        service_security_group: Optional[ec2.ISecurityGroup] = None,
        ecs_subnet_group_name: str = "Private",
        container_port: int = 4000,
        desired_count: int = 0,
        cpu: int = 256,
        memory_mib: int = 512,
        repository_name: str = "ubika-gateway",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        repository = ecr.Repository(
            self,
            "GatewayRepository",
            repository_name=repository_name,
            image_scan_on_push=True,
        )

        cluster = ecs.Cluster(
            self,
            "GatewayCluster",
            vpc=vpc,
            container_insights=True,
        )

        task_definition = ecs.FargateTaskDefinition(
            self,
            "GatewayTaskDefinition",
            cpu=cpu,
            memory_limit_mib=memory_mib,
        )

        log_group = logs.LogGroup(
            self,
            "GatewayServiceLogs",
            retention=logs.RetentionDays.ONE_WEEK,
        )

        container = task_definition.add_container(
            "GatewayContainer",
            image=ecs.ContainerImage.from_ecr_repository(repository),
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="gateway",
                log_group=log_group,
            ),
        )
        container.add_port_mappings(
            ecs.PortMapping(container_port=container_port)
        )

        if service_security_group is None:
            service_security_group = ec2.SecurityGroup(
                self,
                "GatewayServiceSecurityGroup",
                vpc=vpc,
                description="Security group for ECS gateway service",
                allow_all_outbound=True,
            )

        service = ecs.FargateService(
            self,
            "GatewayService",
            cluster=cluster,
            task_definition=task_definition,
            desired_count=desired_count,
            assign_public_ip=False,
            security_groups=[service_security_group],
            vpc_subnets=ec2.SubnetSelection(
                subnet_group_name=ecs_subnet_group_name
            ),
        )

        CfnOutput(
            self,
            "EcrRepositoryUri",
            value=repository.repository_uri,
            description="ECR repository URI",
        )

        CfnOutput(
            self,
            "EcsClusterName",
            value=cluster.cluster_name,
            description="ECS cluster name",
        )

        CfnOutput(
            self,
            "EcsServiceName",
            value=service.service_name,
            description="ECS service name",
        )
