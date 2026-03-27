output "function_name" {
  description = "Name of the scale-toggle Lambda (invoke manually)."
  value       = aws_lambda_function.scale_toggle.function_name
}

output "function_arn" {
  description = "ARN of the scale-toggle Lambda."
  value       = aws_lambda_function.scale_toggle.arn
}

output "invoke_cli_example_stop" {
  description = "Example AWS CLI invoke to scale tasks to 0."
  value       = "aws lambda invoke --function-name ${aws_lambda_function.scale_toggle.function_name} --cli-binary-format raw-in-base64-out --payload '{\"mode\":\"stop\"}' /tmp/out.json && cat /tmp/out.json"
}

output "invoke_cli_example_start" {
  description = "Example AWS CLI invoke to scale tasks to 1."
  value       = "aws lambda invoke --function-name ${aws_lambda_function.scale_toggle.function_name} --cli-binary-format raw-in-base64-out --payload '{\"mode\":\"start\"}' /tmp/out.json && cat /tmp/out.json"
}
