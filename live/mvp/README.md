# MVP (minimal-cost AWS)

Terraform under `live/mvp/` deploys a dedicated **VPC** (cost-optimized: **no NAT Gateway**, **no interface VPC endpoints** by default) and **two EC2 instances** in a **public subnet**:

| Instance | Default type | Role |
|----------|----------------|------|
| **Nginx edge** | `t3.small` (`var.nginx_instance_type`) | Public HTTP(S) reverse proxy on port **80** (Docker runs `nginx:1.27-alpine` from user-data; optional custom image via Makefile). |
| **LiteLLM** | `c7i-flex.large` (`var.instance_type`) | **Postgres** + **LiteLLM** only; publishes **4000** to the VPC for the Nginx host. |

IAM and EC2 are composed from reusable modules: [`modules/ec2-instance-profile-ssm`](../../modules/ec2-instance-profile-ssm) (SSM instance profile) and [`modules/ec2-instance`](../../modules/ec2-instance). Both instances share the **same** EC2 key pair (PEM from Terraform when `generate_ssh_key_pair` is true).

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

3. **Outputs** (browser URL and SSH target for the edge):

   ```bash
   cd live/mvp/litellm/infra
   terraform output -raw nginx_public_ip    # open http://<ip>/ in a browser
   terraform output -raw litellm_private_ip
   ```

4. **Optional — custom Nginx image** (same PEM as Terraform; from repo root):

   ```bash
   make deploy-mvp-nginx-edge
   ```

   This builds [`live/mvp/litellm/nginx-edge/Dockerfile`](litellm/nginx-edge/Dockerfile), copies the image to the **Nginx** host over SSH, and runs it with `LITELLM_HOST` set to the LiteLLM instance **private** IP from Terraform outputs. Requires `docker` and `ssh` on your laptop and `live/mvp/litellm/mvp-litellm-ec2.pem`.

State bucket defaults to `terraform-mvp-591667019512`. Override with `-var=terraform_state_bucket=...` in the litellm stack if needed.

---

## Terraform modules (LiteLLM stack)

- **`modules/ec2-instance-profile-ssm`** — EC2 trust role, `AmazonSSMManagedInstanceCore`, instance profile. The litellm stack attaches extra inline policies (S3 config bucket read, CloudWatch Logs for the agent, optional GitHub deploy key read).
- **`modules/ec2-instance`** — Opinionated `aws_instance`: gp3 root volume, IMDSv2 required, tags.

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

The **LiteLLM** stack reads this state via `terraform_remote_state` and places **both** EC2 instances in a **public subnet** so they can pull images, reach SSM, and (for LiteLLM) clone or read S3 without NAT.

---

## Nginx in this infrastructure

**Role:** Nginx runs on a **dedicated** EC2 instance (`t3.small` by default). It is the **HTTP entry** for browsers and external clients: security group **edge** only attaches to this host (ports **80** / **443**, optional **22** for SSH).

**Mission:**

1. **Edge / demarcation** — Terminate **plain HTTP** at Nginx (TLS is a later step: Cloudflare, ALB, or certs). Clients use `http://<nginx_public_ip>/`.
2. **Reverse proxy to LiteLLM** — Traffic to `/` is forwarded to **`http://<litellm_private_ip>:4000`** (cross-host). Terraform renders [`live/mvp/litellm/infra/nginx-edge.conf.tpl`](litellm/infra/nginx-edge.conf.tpl) with the LiteLLM private IP and uploads it to S3 as `bootstrap/nginx-edge.conf`; **Nginx instance user-data** downloads it and runs `nginx:1.27-alpine` with that file mounted.
3. **Health check** — `GET /health` returns **`ok`** from Nginx without hitting LiteLLM.
4. **Optional Docker image** — [`live/mvp/litellm/nginx-edge/`](litellm/nginx-edge/) contains a **Dockerfile** and `default.conf.template` using `LITELLM_HOST` (env). Use `make deploy-mvp-nginx-edge` from the repo root to rebuild and replace the container on the Nginx host.

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

From the repo root, to **open SSH (port 22) from your public IP** on the **Nginx** host (edge SG):

```bash
make apply-mvp MVP_SSH_INGRESS_CIDR=203.0.113.88/32 TF_APPLY_ARGS=-auto-approve
```

Replace `203.0.113.88/32` with your address (see `curl -s https://checkip.amazonaws.com` + `/32`). Omit `MVP_SSH_INGRESS_CIDR` if you only use Session Manager. SSH uses the **Nginx** instance public IP (same PEM as LiteLLM).

---

## Vercel → EC2

- **Direct**: the **edge** security group allows TCP **80** and **443** from `var.edge_ingress_cidrs` (default `0.0.0.0/0`). Traffic hits the **Nginx** EC2 on **80** first. Use strong app-layer auth; Vercel hobby tier has no fixed egress IPs.
- **Cloudflare Tunnel**: optional `cloudflared` on the **Nginx** host or in compose elsewhere; you can tighten `edge_ingress_cidrs` to VPC-only if all public traffic goes through the tunnel.
- **API Gateway / ALB**: add later in the same VPC and point rules at the Nginx instance or target group.

---

## Security groups (LiteLLM stack)

Defined in `live/mvp/litellm/infra`:

- **edge** — Attached **only** to the **Nginx** EC2. Ingress: **80**, **443** from configured CIDRs; optional **22** from `ssh_ingress_cidrs`. Egress: all.
- **litellm** — Attached **only** to the **LiteLLM** EC2. Ingress: **4000** from the **VPC CIDR** and from the **edge** security group (so the Nginx host can connect). Not open to `0.0.0.0/0` for port 4000.

---

## Connecting to the EC2 instances

**SSH (optional):** open **TCP 22** on the **edge** SG and use the shared PEM against the **Nginx** instance’s **public** IP (or LiteLLM’s public IP if you rely on SSM only — LiteLLM does not need SSH open for public access).

1. **Recommended (no inbound ports): [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)** on either instance (same IAM profile: SSM).

2. **Classic SSH** — set in `live/mvp/litellm/infra` (then `terraform apply`):
   - `generate_ssh_key_pair` (default **true**) — Terraform writes **`live/mvp/litellm/<name>-ec2.pem`** (gitignored). **Both** instances use this key.
   - `ssh_ingress_cidrs` — opens **22** on the **edge** SG (Nginx host).

   ```bash
   chmod 600 live/mvp/litellm/mvp-litellm-ec2.pem
   ssh -i live/mvp/litellm/mvp-litellm-ec2.pem ec2-user@<nginx-public-ip>
   ```

### Session Manager: `docker: command not found`

User data installs **Docker** and **Compose** on first boot. If **`docker` is missing**, see earlier notes: install **Docker** before **`docker-compose-plugin`** in one transaction can fail on some AL2023 AMIs. The litellm templates [`user-data-litellm.sh.tpl`](litellm/infra/user-data-litellm.sh.tpl) and [`user-data-nginx.sh.tpl`](litellm/infra/user-data-nginx.sh.tpl) follow the split install + Compose fallback pattern.

**Fix on a broken instance (as root):**

```bash
dnf install -y docker amazon-cloudwatch-agent awscli
systemctl enable --now docker
dnf install -y docker-compose-plugin || {
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}
docker --version && docker compose version
```

---

## CloudWatch Logs

Log group `/ec2/<name>/system` (see `cloudwatch_log_retention_days`) and the **CloudWatch Agent** on **both** instances ship `/var/log/messages` and `/var/log/cloud-init-output.log`. Adjust `local.cw_agent_json` in [`live/mvp/litellm/infra/main.tf`](litellm/infra/main.tf) to add files.

---

## LiteLLM on EC2 (Docker Compose)

Deployment follows [LiteLLM: Docker, Helm, Terraform](https://docs.litellm.ai/docs/proxy/deploy): **Postgres** + **`litellm-database`** on the **LiteLLM** host; **Nginx** is **not** in this compose file — it runs on the separate EC2. LiteLLM publishes **`4000:4000`** so the Nginx host can reach **`private_ip:4000`**.

### Git clone (default)

With **`use_git_clone = true`** (default in `live/mvp/litellm/infra`):

1. Terraform creates an **ED25519 deploy key** in SSM; output **`github_deploy_public_key_openssh`**.
2. Add the deploy key in GitHub before first successful clone on the **LiteLLM** instance.
3. User data on the **LiteLLM** instance clones the repo and runs **`docker compose up -d`** under **`git_compose_relative_path`** (default `live/mvp/litellm`).
4. The **Nginx** instance is created after the LiteLLM instance; its user-data pulls **`bootstrap/nginx-edge.conf`** (upstream = LiteLLM private IP) and starts Nginx.

Placeholder `.env` on first boot; edit on the **LiteLLM** host (Session Manager), then:

```bash
cd /opt/ubika-infra/live/mvp/litellm && sudo docker compose up -d
```

If you **replace** the LiteLLM instance and its **private IP** changes, run **`terraform apply`** so `nginx-edge.conf` in S3 updates, then **replace the Nginx instance** or re-run **`make deploy-mvp-nginx-edge`**, or on the Nginx host re-fetch S3 and restart the container.

### S3-only bootstrap (optional)

Set **`use_git_clone = false`**. Terraform uploads `docker-compose.yaml` and `config/config.yaml` to S3; **`bootstrap/nginx-edge.conf`** is generated from Terraform with the LiteLLM private IP. User-data on each role pulls the relevant objects.

**If `/opt/litellm` is missing** on the LiteLLM host, run [`scripts/bootstrap-litellm-manual.sh`](litellm/scripts/bootstrap-litellm-manual.sh) (compose + config only; no Nginx on that box).

```bash
cd live/mvp/litellm/infra && terraform output -raw config_bucket_id
# on LiteLLM instance:
export LITELLM_CONFIG_BUCKET="<bucket>"
sudo -E bash /path/to/bootstrap-litellm-manual.sh
```

---

## Egress / NAT

Both instances use a **public subnet** and **public IPv4** for outbound traffic (pulls, SSM, Git) **without a NAT Gateway**.

---

## Second EC2 or more

Reuse `terraform_remote_state` for `mvp/networking` and attach instances to `public_subnet_ids` or `private_subnet_ids` as needed. The reusable EC2 modules live under `modules/ec2-instance-profile-ssm` and `modules/ec2-instance`.
