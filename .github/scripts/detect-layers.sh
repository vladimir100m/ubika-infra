#!/usr/bin/env bash
# detect-layers.sh — Detect changed Terraform layers and output them for GitHub Actions.
#
# Usage: detect-layers.sh <event_name> <base_sha> <head_sha> <exclude_json> [manual_layer]
#
#   event_name    - GitHub event name (push, pull_request, workflow_dispatch)
#   base_sha      - Base commit SHA (used for diff)
#   head_sha      - Head commit SHA (used for diff)
#   exclude_json  - JSON array of layer paths to exclude (e.g. '["production/litellm/bootstrap"]')
#   manual_layer  - (optional) Explicit layer from workflow_dispatch input; skips auto-detection
#
# Outputs (written to $GITHUB_OUTPUT):
#   layers        - JSON array of layer paths to deploy
#   base_sha      - Resolved base SHA
#   head_sha      - Resolved head SHA
set -euo pipefail

EVENT_NAME="${1:?event_name is required}"
BASE_SHA="${2:-}"
HEAD_SHA="${3:?head_sha is required}"
EXCLUDE_LAYERS="${4:-[]}"
MANUAL_LAYER="${5:-}"

filter_layers() {
    local json="$1"
    jq -c --argjson exclude "${EXCLUDE_LAYERS}" '
        map(select((. as $layer | ($exclude | index($layer))) | not))
    ' <<< "$json"
}

# Manual dispatch with an explicit layer overrides auto-detection.
if [[ "$EVENT_NAME" == "workflow_dispatch" && -n "$MANUAL_LAYER" ]]; then
    layers_json="[\"${MANUAL_LAYER}\"]"
    filtered="$(filter_layers "$layers_json")"

    echo "layers=${filtered}" >> "$GITHUB_OUTPUT"
    echo "base_sha=" >> "$GITHUB_OUTPUT"
    echo "head_sha=${HEAD_SHA}" >> "$GITHUB_OUTPUT"
    exit 0
fi

layers_json="$(bash scripts/deploy.sh detect-layers "${BASE_SHA}" "${HEAD_SHA}")"
filtered="$(filter_layers "$layers_json")"

echo "layers=${filtered}" >> "$GITHUB_OUTPUT"
echo "base_sha=${BASE_SHA}" >> "$GITHUB_OUTPUT"
echo "head_sha=${HEAD_SHA}" >> "$GITHUB_OUTPUT"
