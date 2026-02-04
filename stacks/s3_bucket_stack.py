from aws_cdk import (
    CfnOutput,
    RemovalPolicy,
    Stack,
)
from constructs import Construct
import aws_cdk.aws_s3 as s3


class S3BucketStack(Stack):
    """
    Simple S3 bucket stack for storing service requests and artifacts.
    
    Creates:
    - S3 bucket with versioning enabled
    - Block public access enabled
    - Encryption enabled
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name: str = "terraform-ubika-bucket",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket
        bucket = s3.Bucket(
            self,
            "SRBucket",
            bucket_name=bucket_name,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=True,
                block_public_policy=True,
                ignore_public_acls=True,
                restrict_public_buckets=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,  # Delete bucket when stack is destroyed
            auto_delete_objects=True,  # Delete objects when bucket is destroyed
        )

        # Outputs
        CfnOutput(
            self,
            "BucketName",
            value=bucket.bucket_name,
            description="S3 bucket name",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=bucket.bucket_arn,
            description="S3 bucket ARN",
        )

        # Store bucket reference for external use
        self.bucket = bucket
