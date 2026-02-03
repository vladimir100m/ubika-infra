from typing import Optional

from aws_cdk import (
    CfnOutput,
    RemovalPolicy,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_ecr as ecr
import aws_cdk.aws_ecs as ecs
import aws_cdk.aws_iam as iam
import aws_cdk.aws_logs as logs
import aws_cdk.aws_rds as rds
import aws_cdk.aws_secretsmanager as secretsmanager


class ComputeStack(Stack):
    """
    ECS Fargate compute stack with task definition and service.

    Creates:
    - ECS cluster
    - Fargate task definition
    - ECS service (can register with ALB target group)
    - CloudWatch logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        ecr_repository: Optional[ecr.IRepository] = None,
        ecr_repository_uri: Optional[str] = None,
        service_security_group: Optional[ec2.ISecurityGroup] = None,
        db_instance: Optional[rds.IDatabaseInstance] = None,
        db_credentials_secret: Optional[secretsmanager.ISecret] = None,
        db_security_group: Optional[ec2.ISecurityGroup] = None,
        ecs_subnet_group_name: str = "Public",
        container_port: int = 4000,
        desired_count: int = 0,
        cpu: int = 256,
        memory_mib: int = 512,
        litellm_master_key: str = "default-master-key",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Use existing repository or import by URI
        if not ecr_repository and not ecr_repository_uri:
            raise ValueError("Either ecr_repository or ecr_repository_uri must be provided")

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
            runtime_platform=ecs.RuntimePlatform(
                cpu_architecture=ecs.CpuArchitecture.ARM64,
                operating_system_family=ecs.OperatingSystemFamily.LINUX,
            ),
        )

        # Grant ECR permissions to task execution role
        task_definition.add_to_execution_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                resources=["*"],
            )
        )

        # Grant CloudWatch Logs permissions
        task_definition.add_to_execution_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )

        # Grant AWS Bedrock permissions to task role (for LiteLLM to call Bedrock models)
        task_definition.add_to_task_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "bedrock:InvokeModel",
                    "bedrock:InvokeModelWithResponseStream",
                ],
                resources=["*"],
            )
        )

        # Grant Secrets Manager permissions if database credentials are provided
        if db_credentials_secret:
            task_definition.add_to_execution_role_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "secretsmanager:GetSecretValue",
                    ],
                    resources=[db_credentials_secret.secret_arn],
                )
            )

        log_group = logs.LogGroup(
            self,
            "GatewayServiceLogs",
            retention=logs.RetentionDays.ONE_WEEK,
            log_group_name=f"/ecs/ubika-gateway/{self.stack_name}",
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Secrets Manager secret for LITELLM_MASTER_KEY
        litellm_master_key_secret = secretsmanager.Secret(
            self,
            "LiteLLMMasterKeySecret",
            secret_name=f"{self.stack_name}/litellm-master-key",
            secret_string_value=secretsmanager.SecretValue.unsafe_plain_text(
                litellm_master_key
            ),
            description="Master key for LiteLLM proxy authentication",
        )

        # Grant task execution role permission to read the master key secret
        task_definition.add_to_execution_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["secretsmanager:GetSecretValue"],
                resources=[litellm_master_key_secret.secret_arn],
            )
        )

        # Build environment variables
        environment_vars = {
            "AWS_REGION_NAME": "us-east-1",
        }

        # Build secrets (for database URL from Secrets Manager)
        secrets = {
            "LITELLM_MASTER_KEY": ecs.Secret.from_secrets_manager(
                litellm_master_key_secret, "master_key"
            )
        }
        if db_instance and db_credentials_secret:
            # Construct DATABASE_URL from parts
            db_endpoint = db_instance.db_instance_endpoint_address
            db_port = db_instance.db_instance_endpoint_port
            db_name = "litellm"
            
            environment_vars["DB_ENDPOINT"] = db_endpoint
            environment_vars["DB_PORT"] = str(db_port)
            environment_vars["DB_NAME"] = db_name
            
            secrets["DB_USERNAME"] = ecs.Secret.from_secrets_manager(
                db_credentials_secret, "username"
            )
            secrets["DB_PASSWORD"] = ecs.Secret.from_secrets_manager(
                db_credentials_secret, "password"
            )

        container = task_definition.add_container(
            "GatewayContainer",
            image=ecs.ContainerImage.from_registry(ecr_repository_uri) if ecr_repository_uri else ecs.ContainerImage.from_ecr_repository(ecr_repository),
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="gateway",
                log_group=log_group,
            ),
            environment=environment_vars,
            secrets=secrets if secrets else None,
            command=[
                "--config", "/app/config.yaml",
                "--host", "0.0.0.0",
                "--port", str(container_port),
                "--detailed_debug",
            ],
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
            assign_public_ip=True,
            security_groups=[service_security_group],
            vpc_subnets=ec2.SubnetSelection(
                subnet_group_name=ecs_subnet_group_name
            ),
        )

        # Allow ECS tasks to connect to database
        if db_security_group and db_instance:
            db_security_group.add_ingress_rule(
                peer=service_security_group,
                connection=ec2.Port.tcp(5432),  # PostgreSQL default port
                description="Allow ECS tasks to connect to PostgreSQL",
            )

        CfnOutput(
            self,
            "EcsTaskPublicAccessUrl",
            value=f"Note: Access ECS tasks at their public IPs on port {container_port}",
            description="ECS tasks will have public IPs assigned",
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

        CfnOutput(
            self,
            "CloudWatchLogGroup",
            value=log_group.log_group_name,
            description="CloudWatch log group for ECS service",
        )

        CfnOutput(
            self,
            "EcsClusterArn",
            value=cluster.cluster_arn,
            description="ECS cluster ARN",
        )

        CfnOutput(
            self,
            "TaskDefinitionArn",
            value=task_definition.task_definition_arn,
            description="ECS task definition ARN",
        )
