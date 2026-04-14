.PHONY: init-mvp apply-mvp check-mvp-aws

MVPNET := live/mvp/networking
MVPLIT := live/mvp/litellm/infra

# Optional: e.g. make apply-mvp TF_APPLY_ARGS=-auto-approve
TF_INIT_ARGS  ?=
TF_APPLY_ARGS ?=

# Optional: full CIDR for SSH (TCP 22) on the litellm EC2 only, e.g. 203.0.113.88/32 (your public IP + /32).
# Example: make apply-mvp MVP_SSH_INGRESS_CIDR=203.0.113.88/32 TF_APPLY_ARGS=-auto-approve
# Omit to leave ssh_ingress_cidrs unset (Terraform default: no SSH from the internet; use Session Manager).
MVP_SSH_INGRESS_CIDR ?=

# Match AWS CLI behavior for SSO / ~/.aws/config: load config file + named profile.
# Stale AWS_ACCESS_KEY_* in the shell overrides the profile chain — unset for MVP commands only.
MVP_AWS_PROFILE ?= ubika-terraform
MVP_AWS_SHELL = bash -eo pipefail -c 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN; export AWS_SDK_LOAD_CONFIG=1 AWS_PROFILE=$(MVP_AWS_PROFILE); exec "$$@"' _

## Sanity-check the same env Terraform will use (override profile: make check-mvp-aws MVP_AWS_PROFILE=other).
check-mvp-aws:
	@if [ -n "$$AWS_ACCESS_KEY_ID" ] || [ -n "$$AWS_SECRET_ACCESS_KEY" ] || [ -n "$$AWS_SESSION_TOKEN" ]; then \
		printf '%s\n' \
		  ">>> Shell has AWS_ACCESS_KEY_* / AWS_SESSION_TOKEN set; unset them or they override SSO/profile."; \
	fi
	$(MVP_AWS_SHELL) aws sts get-caller-identity

## Initialize Terraform backends for both MVP stacks (networking, then litellm).
init-mvp: check-mvp-aws
	cd $(MVPNET) && $(MVP_AWS_SHELL) terraform init -backend-config=backend.hcl -input=false $(TF_INIT_ARGS)
	cd $(MVPLIT) && $(MVP_AWS_SHELL) terraform init -backend-config=backend.hcl -input=false $(TF_INIT_ARGS)

## Apply MVP stacks in order: networking first, then litellm.
## If MVP_SSH_INGRESS_CIDR is set, passes -var='ssh_ingress_cidrs=["<cidr>"]' for litellm only (needed for SSH from your IP).
apply-mvp:
	cd $(MVPNET) && $(MVP_AWS_SHELL) terraform apply -input=false $(TF_APPLY_ARGS)
	cd $(MVPLIT) && $(MVP_AWS_SHELL) terraform apply -input=false $(TF_APPLY_ARGS) $(if $(MVP_SSH_INGRESS_CIDR),-var='ssh_ingress_cidrs=["$(MVP_SSH_INGRESS_CIDR)"]',)
