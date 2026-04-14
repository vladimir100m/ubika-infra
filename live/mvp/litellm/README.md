# MVP LiteLLM (app + infra)

- **`infra/`** — Terraform (EC2, S3 config bucket, IAM, user data). Run `terraform init` / `apply` from this directory (`backend.hcl` lives here).
- **`docker-compose.yaml`**, **`config/`**, **`nginx/`** — runtime stack; also synced to S3 when `use_git_clone = false`.
- **`scripts/`** — helpers (e.g. manual bootstrap on the instance).

See `../README.md` for deploy order and AWS profile.
