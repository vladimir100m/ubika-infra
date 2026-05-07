#!/bin/bash
set -euxo pipefail
mkdir -p /opt/nginx-edge
touch /var/log/nginx-edge-bootstrap.log
exec >> /var/log/nginx-edge-bootstrap.log 2>&1
echo "=== nginx edge bootstrap start $(date -Is) ==="

dnf install -y docker amazon-cloudwatch-agent awscli
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
echo '${cw_agent_b64}' | base64 -d > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

aws s3 cp "s3://${bootstrap_bucket}/bootstrap/nginx-edge.conf" /opt/nginx-edge/default.conf --region ${aws_region}

docker rm -f mvp-nginx-edge 2>/dev/null || true
docker pull nginx:1.27-alpine
docker run -d --name mvp-nginx-edge --restart unless-stopped \
  -p 80:80 \
  -v /opt/nginx-edge/default.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:1.27-alpine

echo "=== nginx edge bootstrap done $(date -Is) ==="
