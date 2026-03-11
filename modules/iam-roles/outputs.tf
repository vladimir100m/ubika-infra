output "execution_role_arn" {
  description = "ARN of the ECS Task Execution Role."
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Name of the ECS Task Execution Role."
  value       = aws_iam_role.execution.name
}

output "task_role_arn" {
  description = "ARN of the ECS Task Role."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the ECS Task Role."
  value       = aws_iam_role.task.name
}
