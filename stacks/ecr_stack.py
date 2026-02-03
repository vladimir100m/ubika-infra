from aws_cdk import (
    CfnOutput,
    RemovalPolicy,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_ecr as ecr


class EcrStack(Stack):
    """
    ECR repository stack for container images.
    
    Separate from compute to allow independent management.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        repository_name: str = "ubika-gateway",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.repository = ecr.Repository(
            self,
            "GatewayRepository",
            repository_name=repository_name,
            image_scan_on_push=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

        CfnOutput(
            self,
            "RepositoryUri",
            value=self.repository.repository_uri,
            description="ECR repository URI",
            export_name="UbikaGatewayRepositoryUri",
        )

        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="ECR repository name",
            export_name="UbikaGatewayRepositoryName",
        )
