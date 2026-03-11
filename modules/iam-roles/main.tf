# ---------------------------------------------------------------------------
# Module: iam-roles
#
# Provisions the two standard ECS IAM roles every service needs:
#
#   1. Task Execution Role  – used by the ECS agent to:
#                              - Pull images from ECR
#                              - Write logs to CloudWatch
#                              - Read secrets from Secrets Manager at start-up
#
#   2. Task Role            – used by the running container to:
#                              - Call AWS APIs (Bedrock, S3, DynamoDB, etc.)
#                              - Scoped strictly to what the app needs
#
# NEVER merge these two roles. Their trust principals and permission scopes
# are fundamentally different.
# ---------------------------------------------------------------------------

# Placeholder – implement when adding the first ECS service.
