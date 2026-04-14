#!/bin/bash
set -euxo pipefail
# Dirs and log must exist before exec: a failed early step can exit the script before mkdir runs.
mkdir -p /opt/litellm/nginx
chmod 755 /opt/litellm
touch /var/log/litellm-bootstrap.log
exec >> /var/log/litellm-bootstrap.log 2>&1
echo "=== litellm bootstrap start $(date -Is) ==="

dnf install -y docker amazon-cloudwatch-agent awscli docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
echo '${cw_agent_b64}' | base64 -d > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

%{ if use_git_clone ~}
dnf install -y git
mkdir -p /root/.ssh
chmod 700 /root/.ssh
aws ssm get-parameter --name "${github_deploy_ssm_name}" --with-decryption --region ${aws_region} --query Parameter.Value --output text > /root/.ssh/id_ed25519_github
chmod 600 /root/.ssh/id_ed25519_github
ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts
export GIT_SSH_COMMAND='ssh -i /root/.ssh/id_ed25519_github -o IdentitiesOnly=yes'
if [[ -d "${git_clone_path}/.git" ]]; then
  cd "${git_clone_path}" && git fetch origin && git checkout "${git_branch}" && git pull --ff-only
else
  git clone --branch "${git_branch}" "${git_repo_ssh_url}" "${git_clone_path}"
fi
chown -R ec2-user:ec2-user "${git_clone_path}"

COMPOSE_DIR="${git_clone_path}/${git_compose_relative_path}"
if [[ ! -f "$${COMPOSE_DIR}/.env" ]]; then
  cat > "$${COMPOSE_DIR}/.env" <<'ENVEOF'
LITELLM_MASTER_KEY=sk-mvp-change-me
LITELLM_SALT_KEY=replace-with-long-random-string-use-openssl-rand-hex-32
STORE_MODEL_IN_DB=true
OPENAI_API_KEY=
ENVEOF
  chmod 600 "$${COMPOSE_DIR}/.env"
fi

cd "$${COMPOSE_DIR}"
docker compose up -d
%{ else ~}
# Terraform fills bucket/region at render time (no bash $ conflict).
aws s3 cp "s3://${bootstrap_bucket}/bootstrap/docker-compose.yaml" /opt/litellm/docker-compose.yaml --region ${aws_region}
aws s3 cp "s3://${bootstrap_bucket}/bootstrap/config.yaml" /opt/litellm/config.yaml --region ${aws_region}
aws s3 cp "s3://${bootstrap_bucket}/bootstrap/nginx.conf" /opt/litellm/nginx/default.conf --region ${aws_region}

if [[ ! -f /opt/litellm/.env ]]; then
  cat > /opt/litellm/.env <<'ENVEOF'
LITELLM_MASTER_KEY=sk-mvp-change-me
LITELLM_SALT_KEY=replace-with-long-random-string-use-openssl-rand-hex-32
STORE_MODEL_IN_DB=true
OPENAI_API_KEY=
ENVEOF
  chmod 600 /opt/litellm/.env
fi

cd /opt/litellm
docker compose up -d
%{ endif ~}

echo "=== litellm bootstrap done $(date -Is) ==="

${extra_user_data}
