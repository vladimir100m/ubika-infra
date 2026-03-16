#!/usr/bin/env bash
set -euo pipefail

# ... [Keep your SHA Resolution Logic exactly as it is, it's perfect] ...

# --- EXECUTION ---
if [[ "$EVENT_NAME" == "workflow_dispatch" && -n "$MANUAL_LAYER" ]]; then
    CLEAN_LAYER="${MANUAL_LAYER#live/}"
    layers_json="[\"${CLEAN_LAYER}\"]"
else
    # Capture output and ensure it is valid JSON
    layers_json="$(bash scripts/deploy.sh detect-layers "${RESOLVED_BASE}" "${HEAD_SHA}" || echo "[]")"
fi

# Apply weighted sorting + Deduplication
# Added a check to ensure we are dealing with an array
ORDERED_JSON=$(echo "${layers_json:-[]}" | jq -c 'if type == "array" then sort_by(
    if contains("networking") then 1
    elif contains("iam") then 2
    elif (contains("rds") or (contains("redis") or contains("elasticache"))) then 3
    elif contains("litellm") then 5
    elif contains("agents") then 6
    else 9 end
) | unique else [] end')

filtered="$(filter_layers "$ORDERED_JSON")"

# Generate the folder list for Docker jobs (e.g., live/production/agents)
# This maps a layer (production/agents/infra) to its base folder (live/production/agents)
folders_json=$(echo "$filtered" | jq -c 'map("live/" + (split("/") | .[0:2] | join("/"))) | unique')

emit_output "layers" "$filtered"
emit_output "folders" "$folders_json"
emit_output "has_changes" "$([[ "$filtered" != "[]" ]] && echo "1" || echo "0")"
emit_output "base_sha" "$RESOLVED_BASE"
emit_output "head_sha" "$HEAD_SHA"