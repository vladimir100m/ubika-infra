# MVP (minimal-cost AWS)

Terraform under `live/mvp/` deploys a dedicated **VPC** (cost-optimized: **no NAT Gateway**, **no interface VPC endpoints** by default) and a single **EC2** instance that runs **Docker Compose**: **Nginx** (public HTTP edge), **LiteLLM** (proxy API, internal port), and **Postgres**.

---

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

---

## Networking (MVP)

The MVP stack uses `modules/networking` from `live/mvp/networking/main.tf` with these settings:

| Setting | MVP value | Purpose |
|--------|-----------|--------|
| `enable_nat_gateway` | `false` | Avoid NAT Gateway hourly + data charges; workloads that need the internet use a **public subnet** + **IGW** instead. |
| `enable_interface_vpc_endpoints` | `false` | No paid **interface** endpoints (Secrets Manager, ECR, Logs, STS, etc.); saves per-AZ cost. |
| `enable_s3_gateway_endpoint` | `true` | **S3 gateway endpoint** (no hourly charge) so S3 traffic can stay on the AWS backbone where applicable. |
| `enable_vpc_flow_logs` | `false` | No VPC Flow Logs / extra log storage for MVP (enable in the module when you need audit or troubleshooting). |

### What the networking module creates (new VPC)

When `vpc_id` is empty, Terraform creates a **new VPC** (`10.0.0.0/16` by default in the module) and:

- **VPC** — DNS hostnames and DNS support enabled.
- **Internet Gateway (IGW)** — attachment to that VPC.
- **Subnets** — typically **two public** and **two private** subnets across two AZs (CIDRs derived via `cidrsubnet` from the VPC block).
- **Route tables**
  - **Public**: default route `0.0.0.0/0` → **IGW** (subnets with `map_public_ip_on_launch = true`).
  - **Private** — with **NAT disabled** (MVP): isolated private route tables **without** a default route to the internet (no NAT Gateway is created). If you later enable NAT in the module, private subnets can use a NAT route instead.
- **NAT Gateway / Elastic IPs** — **not** created for MVP (`enable_nat_gateway = false`), so no NAT-related resources.
- **S3 Gateway VPC Endpoint** — `com.amazonaws.<region>.s3`, **Gateway** type, associated with the relevant **route tables** (public + private in the module’s logic) so S3 can be reached without traversing the public internet for that path, at no hourly endpoint fee.

### Optional module features (not used in default MVP)

The same module can also create (when flags are turned on):

- **NAT Gateway(s)** and **EIPs** — for private-subnet egress without public IPs.
- **Interface VPC endpoints** — `secretsmanager`, `ecr.api`, `ecr.dkr`, `logs`, `sts`, plus a **security group** for endpoint ENIs (`443` from the VPC CIDR).
- **VPC Flow Logs** — to CloudWatch Logs, with an **IAM role** for log delivery.

MVP does **not** deploy those unless you change the `module "networking"` inputs in `live/mvp/networking/main.tf`.

### Outputs (networking stack)

Useful values for other stacks or docs:

- `vpc_id`
- `public_subnet_ids`
- `private_subnet_ids`

The **LiteLLM** stack reads this state via `terraform_remote_state` and places the EC2 instance in a **public subnet** so it can reach Docker registries, GitHub, SSM, etc., without NAT.

---

## Nginx in this infrastructure

**Role:** Nginx is the **only HTTP entrypoint** intended for browsers and external HTTP clients. It listens on **port 80** inside Docker and is mapped to **host port 80**, which matches the AWS **edge** security group (ingress `80` / `443` from configured CIDRs).

**Mission:**

1. **Edge / demarcation** — Terminate **plain HTTP** at Nginx (default `docker-compose` does not configure TLS inside the container). HTTPS at the edge is usually added later (reverse proxy, Cloudflare, ALB, or cert on the host). Until then, clients use `http://<public-ip>/`.
2. **Reverse proxy to LiteLLM** — All application traffic under `/` is forwarded to the **`litellm`** service on **port 4000** on the Docker network (`proxy_pass http://litellm:4000`), with `Host`, `X-Forwarded-*`, and timeouts suitable for LLM requests.
3. **Health check** — `GET /health` returns a static **`ok`** response from Nginx itself so load balancers and monitors can verify the edge without hitting the LLM app.
4. **Stable public surface** — External systems (e.g. Vercel, scripts) target **one host and port** (80); LiteLLM stays **off** the public internet at the security-group level except where allowed by the **litellm** security group rules (VPC + edge SG).

Config file in-repo: `live/mvp/litellm/nginx/nginx.conf` (also uploaded to S3 when using S3 bootstrap).

---

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

---

## Vercel → EC2

- **Direct**: the **edge** security group allows TCP **80** and **443** from `var.edge_ingress_cidrs` (default `0.0.0.0/0`). Traffic hits **Nginx** on **80** first. Use strong app-layer auth; Vercel hobby tier has no fixed egress IPs.
- **Cloudflare Tunnel**: optional `cloudflared` service in `docker-compose.yaml`; you can tighten `edge_ingress_cidrs` to VPC-only if all public traffic goes through the tunnel (document your chosen ports).
- **API Gateway / ALB**: add later in the same VPC and point rules at the instance or target group.

---

## Security groups (LiteLLM stack)

These are defined in `live/mvp/litellm/infra`, not in the networking module:

- **edge** — Ingress from the internet (or chosen CIDRs) to **Nginx / agent** ports (e.g. **80**, **443**); optional **22** when `ssh_ingress_cidrs` is set. Egress allow-all for pulls and outbound services.
- **litellm** — LiteLLM’s port (**4000**) reachable from the **VPC CIDR** and from the **edge** security group (same instance), **not** open to `0.0.0.0/0`.

---

## Connecting to the EC2 instance

**SSH was not enabled by default:** the security group only allowed HTTP(S). Console “SSH” / **EC2 Instance Connect** still needs **TCP 22** open and usually an **EC2 key pair**.

1. **Recommended (no inbound ports): [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)**  
   EC2 → instance → **Connect** → **Session Manager**. Requires the instance profile (`AmazonSSMManagedInstanceCore`), outbound internet in a public subnet, and the SSM agent (preinstalled on AL2023).

2. **Classic SSH** — set in `live/mvp/litellm/infra` (then `terraform apply`):
   - `generate_ssh_key_pair` (default **true**) — Terraform creates an RSA key, registers **`${name}-ec2`** in EC2, and writes the private key to **`live/mvp/litellm/<name>-ec2.pem`** (gitignored). Use `-var=generate_ssh_key_pair=false` and `ec2_key_name=...` to use an existing key instead.
   - `ssh_ingress_cidrs` — e.g. `["203.0.113.10/32"]` (your public IP); required for SSH from the internet.
   Then: `chmod 600 live/mvp/litellm/mvp-litellm-ec2.pem` and `ssh -i live/mvp/litellm/mvp-litellm-ec2.pem ec2-user@<public-dns-or-ip>`.

---

## CloudWatch Logs

The litellm stack creates log group `/ec2/<name>/system` (see `cloudwatch_log_retention_days`) and installs the **CloudWatch Agent** on boot to ship `/var/log/messages` and `/var/log/cloud-init-output.log`. Streams are named with `{instance_id}` placeholders. Adjust `local.cw_agent_json` in `live/mvp/litellm/infra/main.tf` to add files or use the agent’s metrics support.

---

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

---

## Egress / NAT

The EC2 instance is in a **public subnet** with a **public IPv4** so it can pull images and use outbound-only patterns (e.g. tunnel) **without a NAT Gateway**. Private subnets in this VPC have **no** default route to the internet unless you add NAT or endpoints later.

---

## Second EC2

Reuse `terraform_remote_state` for `mvp/networking` and attach instances to `private_subnet_ids` or `public_subnet_ids` as needed. Private subnets without NAT still need a path for Docker Hub or use ECR + endpoints.
