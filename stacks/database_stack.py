from aws_cdk import (
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    SecretValue,
)
from constructs import Construct
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_rds as rds
import aws_cdk.aws_secretsmanager as secretsmanager


class DatabaseStack(Stack):
    """
    RDS PostgreSQL database stack for LiteLLM proxy.
    
    Creates:
    - PostgreSQL RDS instance (free tier eligible: db.t3.micro)
    - Database credentials in Secrets Manager
    - Security group for database access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc: ec2.IVpc,
        database_name: str = "litellm",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Security group for RDS
        self.db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=vpc,
            description="Security group for LiteLLM PostgreSQL database",
            allow_all_outbound=False,
        )

        # Create database credentials secret
        db_credentials_secret = secretsmanager.Secret(
            self,
            "DBCredentialsSecret",
            secret_name=f"{construct_id}/db-credentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username":"litellm_admin"}',
                generate_string_key="password",
                exclude_characters='/@" \\\'',
                password_length=32,
            ),
            description="Database credentials for LiteLLM",
        )

        # PostgreSQL RDS instance
        # Using db.t3.micro for free tier eligibility
        self.db_instance = rds.DatabaseInstance(
            self,
            "LiteLLMDatabase",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO,
            ),
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            security_groups=[self.db_security_group],
            database_name=database_name,
            credentials=rds.Credentials.from_secret(db_credentials_secret),
            allocated_storage=20,  # Free tier: up to 20 GB
            max_allocated_storage=20,  # Disable autoscaling for cost control
            publicly_accessible=False,  # Only accessible from VPC
            deletion_protection=False,  # Allow deletion for MVP
            removal_policy=RemovalPolicy.DESTROY,  # Auto-delete on stack deletion
            backup_retention=Duration.days(0),  # No backups for MVP (saves cost)
            multi_az=False,  # Single AZ for free tier
        )

        # Store connection string format in Secrets Manager
        self.connection_string_secret = secretsmanager.Secret(
            self,
            "DBConnectionStringSecret",
            secret_name=f"{construct_id}/connection-string",
            secret_string_value=SecretValue.unsafe_plain_text(
                f"postgresql://litellm_admin:{{password}}@{self.db_instance.db_instance_endpoint_address}:{self.db_instance.db_instance_endpoint_port}/{database_name}"
            ),
            description="PostgreSQL connection string template for LiteLLM",
        )

        # Outputs
        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.db_instance.db_instance_endpoint_address,
            description="RDS PostgreSQL endpoint",
        )

        CfnOutput(
            self,
            "DatabasePort",
            value=str(self.db_instance.db_instance_endpoint_port),
            description="RDS PostgreSQL port",
        )

        CfnOutput(
            self,
            "DatabaseName",
            value=database_name,
            description="Database name",
        )

        CfnOutput(
            self,
            "DatabaseCredentialsSecretArn",
            value=db_credentials_secret.secret_arn,
            description="ARN of the database credentials secret",
        )

        CfnOutput(
            self,
            "DatabaseSecurityGroupId",
            value=self.db_security_group.security_group_id,
            description="Database security group ID",
        )
