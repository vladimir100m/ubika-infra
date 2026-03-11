variable "name" {
  description = "Name prefix for the IAM roles (e.g. 'genai-gateway-my-service')."
  type        = string
}

variable "task_role_policy_arns" {
  description = "List of IAM policy ARNs to attach to the Task Role (runtime app permissions)."
  type        = list(string)
  default     = []
}

variable "extra_execution_role_policy_arns" {
  description = "Additional policy ARNs to attach to the Task Execution Role beyond the AWS managed baseline."
  type        = list(string)
  default     = []
}
