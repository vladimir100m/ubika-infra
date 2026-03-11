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
  description = "Additional managed policy ARNs to attach to the Task Execution Role beyond the AWS baseline."
  type        = list(string)
  default     = []
}

variable "extra_secrets_arns" {
  description = "List of Secrets Manager ARNs the Task Execution Role must be able to read at container start-up."
  type        = list(string)
  default     = []
}
