# MVP (minimal-cost AWS)

Terraform under `live/mvp/` deploys a small VPC (no NAT, no paid interface VPC endpoints, S3 gateway endpoint kept) and a single EC2 instance for Agents / Nginx / LiteLLM-style workloads.

## Deploy order

1. **Networking** (`live/mvp/networking`)

   ```bash
   cd live/mvp/networking
   terraform init -backend-config=backend.hcl
   terraform plan
   terraform apply
   ```

2. **Compute + S3** (`live/mvp/litellm/infra` — Terraform; app files stay in `live/mvp/litellm/`)

   ```bash
   cd live/mvp/litellm/infra
   terraform init -backend-config=backend.hcl
   terraform plan
   terraform apply
   ```

State bucket defaults to `terraform-mvp-591667019512`. Override with `-var=terraform_state_bucket=...` in the litellm stack if needed.

## AWS profile

MVP Terraform uses the **default provider credential chain** with env vars set by `make init-mvp` / `make apply-mvp`: `AWS_PROFILE=ubika-terraform` and `AWS_SDK_LOAD_CONFIG=1` (so SSO and `~/.aws/config` behave like the AWS CLI).

Run Terraform by hand from the repo root:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
export AWS_SDK_LOAD_CONFIG=1 AWS_PROFILE=ubika-terraform
cd live/mvp/networking && terraform init -backend-config=backend.hcl
```

Override the profile: `make check-mvp-aws MVP_AWS_PROFILE=my-profile`.

From the repo root, to **open SSH (port 22) from your public IP** on the litellm stack only:

```bash
make apply-mvp MVP_SSH_INGRESS_CIDR=203.0.113.88/32 TF_APPLY_ARGS=-auto-approve
```

Replace `203.0.113.88/32` with your address (see `curl -s https://checkip.amazonaws.com` + `/32`). Omit `MVP_SSH_INGRESS_CIDR` if you only use Session Manager.

## Vercel → EC2

- **Direct**: security group `edge` allows TCP `80` and `443` from `var.edge_ingress_cidrs` (default `0.0.0.0/0`). Use strong app-layer auth; Vercel hobby tier has no fixed egress IPs.
- **Cloudflare Tunnel**: optional `cloudflared` service in `docker-compose.yaml`; you can tighten `edge_ingress_cidrs` to VPC-only if all public traffic goes through the tunnel (document your chosen ports).
- **API Gateway / ALB**: add later in the same VPC and point rules at the instance or target group.

## Security groups

- **edge**: external callers → Nginx / Agent ports only.
- **litellm**: LiteLLM port restricted to VPC CIDR and referencing the edge SG (not open to the world).

## Connecting to the EC2 instance

**SSH was not enabled by default:** the security group only allowed HTTP(S). Console “SSH” / **EC2 Instance Connect** still needs **TCP 22** open and usually an **EC2 key pair**.

1. **Recommended (no inbound ports): [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)**  
   EC2 → instance → **Connect** → **Session Manager**. Requires the instance profile (`AmazonSSMManagedInstanceCore`), outbound internet in a public subnet, and the SSM agent (preinstalled on AL2023).

2. **Classic SSH** — set in `live/mvp/litellm/infra` (then `terraform apply`):
   - `generate_ssh_key_pair` (default **true**) — Terraform creates an RSA key, registers **`${name}-ec2`** in EC2, and writes the private key to **`live/mvp/litellm/<name>-ec2.pem`** (gitignored). Use `-var=generate_ssh_key_pair=false` and `ec2_key_name=...` to use an existing key instead.
   - `ssh_ingress_cidrs` — e.g. `["203.0.113.10/32"]` (your public IP); required for SSH from the internet.
   Then: `chmod 600 live/mvp/litellm/mvp-litellm-ec2.pem` and `ssh -i live/mvp/litellm/mvp-litellm-ec2.pem ec2-user@<public-dns-or-ip>`.

## CloudWatch Logs

The litellm stack creates log group `/ec2/<name>/system` (see `cloudwatch_log_retention_days`) and installs the **CloudWatch Agent** on boot to ship `/var/log/messages` and `/var/log/cloud-init-output.log`. Streams are named with `{instance_id}` placeholders. Adjust `local.cw_agent_json` in `live/mvp/litellm/infra/main.tf` to add files or use the agent’s metrics support.

## LiteLLM on EC2 (Docker Compose)

Deployment follows [LiteLLM: Docker, Helm, Terraform](https://docs.litellm.ai/docs/proxy/deploy): **Postgres** + **`litellm-database`** image + **Nginx** on port 80 proxying to the proxy on 4000.

### Git clone (default)

With **`use_git_clone = true`** (default in `live/mvp/litellm/infra`):

1. Terraform creates an **ED25519 deploy key**, stores the **private key** in **SSM Parameter Store** (`SecureString`), and grants the EC2 role **`ssm:GetParameter`** on that parameter only. The **public key** is an output: **`github_deploy_public_key_openssh`**.
2. **Before the instance first clones successfully**, add that public key in GitHub: **repository → Settings → Deploy keys → Add deploy key** (read-only). If the instance already booted and clone failed, add the key and **replace the instance** or fix manually on the host (`git clone` / `git pull` in `/opt/ubika-infra`).
3. **User data** installs Docker, the **Compose plugin**, CloudWatch agent, and **git**; fetches the deploy key from SSM; clones **`git_repo_ssh_url`** (default `git@github.com:vladimir100m/ubika-infra.git`) to **`git_clone_path`** (default `/opt/ubika-infra`); runs **`docker compose up -d`** in **`git_compose_relative_path`** (default `live/mvp/litellm`).
4. On first boot, if `.env` is missing under that compose directory, a **placeholder** is created. **Edit it on the instance** (Session Manager): set **`LITELLM_MASTER_KEY`**, **`LITELLM_SALT_KEY`**, and **`OPENAI_API_KEY`**, then:

   ```bash
   cd /opt/ubika-infra/live/mvp/litellm && sudo docker compose up -d
   ```

Override clone URL, branch, or paths with `-var='git_repo_ssh_url=...'`, `git_branch`, `git_clone_path`, `git_compose_relative_path`.

### S3-only bootstrap (optional)

Set **`use_git_clone = false`**. Then Terraform uploads `docker-compose.yaml`, `config/config.yaml`, and `nginx/nginx.conf` to the **config S3 bucket** under `bootstrap/`, and **user data** uses `aws s3 cp` into `/opt/litellm` and runs **`docker compose up -d`** there (same placeholder `.env` behavior under `/opt/litellm`).

To change compose or config for future boots, update files in this repo, run `terraform apply`, then replace the instance or sync files manually and `docker compose up -d` again.

**If `/opt/litellm` is missing:** the current instance may have been created **before** bootstrap was added, or **user data failed** early (check `sudo tail -200 /var/log/cloud-init-output.log` and `/var/log/litellm-bootstrap.log`). Fix: **`terraform apply`** so the instance is **replaced** and new user data runs, or run the manual script on the server:

```bash
# from repo, get bucket name:
cd live/mvp/litellm/infra && terraform output -raw config_bucket_id

# on the instance (Session Manager), after copying scripts/bootstrap-litellm-manual.sh or pasting its contents:
export LITELLM_CONFIG_BUCKET="<that-bucket-id>"
export AWS_REGION="us-east-1"
sudo -E bash bootstrap-litellm-manual.sh
```

**Note:** Docs recommend pinning image tags (e.g. `main-stable`) for production; the compose file uses `docker.litellm.ai/berriai/litellm-database:main-stable`.

## Egress / NAT

The EC2 instance is in a **public subnet** with a **public IPv4** so it can pull images and use outbound-only patterns (e.g. tunnel) **without a NAT Gateway**. Private subnets in this VPC have **no** default route to the internet unless you add NAT or endpoints later.

## Second EC2

Reuse `terraform_remote_state` for `mvp/networking` and attach instances to `private_subnet_ids` or `public_subnet_ids` as needed. Private subnets without NAT still need a path for Docker Hub or use ECR + endpoints.
