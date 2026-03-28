#!/usr/bin/env bash
set -euo pipefail
RG="${rg_id}"
REGION="${region}"
DESIRED="${desired}"
ENABLED="${enabled}"

if [[ "$ENABLED" != "true" ]]; then
  echo "[elasticache-redis] pre-modify: disabled (pre_modify_disable_failover_via_cli=false), skipping"
  exit 0
fi

if [[ "$DESIRED" != "1" ]]; then
  echo "[elasticache-redis] pre-modify: desired node count is not 1, skipping CLI failover step"
  exit 0
fi

if ! aws elasticache describe-replication-groups --replication-group-id "$RG" --region "$REGION" &>/dev/null; then
  echo "[elasticache-redis] pre-modify: replication group not found yet (initial create), skipping"
  exit 0
fi

NUM_NODES=$(aws elasticache describe-replication-groups --replication-group-id "$RG" --region "$REGION" \
  --query 'ReplicationGroups[0].MemberClusters | length(@)' --output text)
FAILOVER=$(aws elasticache describe-replication-groups --replication-group-id "$RG" --region "$REGION" \
  --query 'ReplicationGroups[0].AutomaticFailover' --output text)

if [[ -z "$NUM_NODES" || "$NUM_NODES" -le 1 ]]; then
  echo "[elasticache-redis] pre-modify: already single-node, skipping"
  exit 0
fi

if [[ "$FAILOVER" != "enabled" ]]; then
  echo "[elasticache-redis] pre-modify: automatic failover not enabled ($FAILOVER), skipping"
  exit 0
fi

echo "[elasticache-redis] pre-modify: disabling automatic failover before Terraform removes replica(s)"
aws elasticache modify-replication-group \
  --replication-group-id "$RG" \
  --region "$REGION" \
  --no-automatic-failover-enabled \
  --no-multi-az-enabled \
  --apply-immediately
aws elasticache wait replication-group-available --replication-group-id "$RG" --region "$REGION"
echo "[elasticache-redis] pre-modify: replication group available, Terraform may update node count"
