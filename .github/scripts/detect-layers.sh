#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${1:?event_name is required}"
BASE_SHA="${2:-}"
HEAD_SHA="${3:?head_sha is required}"
EXCLUDE_LAYERS="${4:-[]}"
MANUAL_LAYER="${5:-}"

emit_output() {
    local key="$1"
    local value="$2"
    [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "${key}=${value}" >> "$GITHUB_OUTPUT"
    echo "[detect-layers] OUTPUT: ${key}=${value}"
}

# --- SHA RESOLUTION LOGIC ---
# Fixes the "fatal: ambiguous argument" error
if [[ -z "$BASE_SHA" ]] || [[ "$BASE_SHA" == "0000000000000000000000000000000000000000" ]] || ! git rev-parse --verify "$BASE_SHA" >/dev/null 2>&1; then
    echo "[detect-layers] BASE_SHA is invalid or missing. Attempting recovery..."
    
    # Check if there is a parent commit
    if git rev-parse HEAD~1 >/dev/null 2>&1; then
        RESOLVED_BASE=$(git rev-parse HEAD~1)
    else
        # If it's the first commit, compare against the magic empty tree
        RESOLVED_BASE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    fi
else
    RESOLVED_BASE="$BASE_SHA"
fi

echo "[detect-layers] RESOLVED_BASE=${RESOLVED_BASE}"

filter_layers() {
    local json="$1"
    # Ensure we handle empty/invalid JSON from the sub-script
    if [[ -z "$json" ]] || [[ "$json" == "null" ]]; then json="[]"; fi
    jq -c --argjson exclude "${EXCLUDE_LAYERS}" '
        map(select((. as $layer | ($exclude | index($layer))) | not))
    ' <<< "$json"
}

# --- EXECUTION ---
if [[ "$EVENT_NAME" == "workflow_dispatch" && -n "$MANUAL_LAYER" ]]; then
    # Clean manual layer path (remove live/ prefix if user added it)
    CLEAN_LAYER="${MANUAL_LAYER#live/}"
    layers_json="[\"${CLEAN_LAYER}\"]"
else
    # Call your deployment script with the RESOLVED base
    layers_json="$(bash scripts/deploy.sh detect-layers "${RESOLVED_BASE}" "${HEAD_SHA}")"
fi

# Apply the weighted sorting we discussed earlier
# This ensures networking -> litellm -> agents
ORDERED_JSON=$(echo "$layers_json" | jq -c 'sort_by(
    if contains("networking") then 1
    elif contains("iam") then 2
    elif (contains("rds") or contains("redis")) then 3
    elif contains("litellm") then 5
    elif contains("agents") then 6
    else 9 end
)')

filtered="$(filter_layers "$ORDERED_JSON")"

emit_output "layers" "$filtered"
emit_output "base_sha" "$RESOLVED_BASE"
emit_output "head_sha" "$HEAD_SHA"
