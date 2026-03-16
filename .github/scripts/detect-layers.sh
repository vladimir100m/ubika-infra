#!/usr/bin/env bash
set -euo pipefail

# --- ARGUMENTS WITH DEFAULTS ---
# Using ${VAR:-default} prevents "unbound variable" errors
EVENT_NAME="${1:-}"
BASE_SHA="${2:-}"
HEAD_SHA="${3:-}"
EXCLUDE_LAYERS="${4:-[]}"
MANUAL_LAYER="${5:-}"
FORCE_DOCKER="${6:-false}"
DOCKER_FOLDER="${7:-}"

# Validation for mandatory fields
: "${EVENT_NAME:?event_name is required}"
: "${HEAD_SHA:?head_sha is required}"

emit_output() {
    local key="$1"
    local value="$2"
    [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "${key}=${value}" >> "$GITHUB_OUTPUT"
    echo "[detect-layers] OUTPUT: ${key}=${value}"
}

# --- SHA RESOLUTION LOGIC ---
if [[ -z "$BASE_SHA" ]] || [[ "$BASE_SHA" == "0000000000000000000000000000000000000000" ]] || ! git rev-parse --verify "$BASE_SHA" >/dev/null 2>&1; then
    echo "[detect-layers] BASE_SHA is invalid or missing. Attempting recovery..."
    if git rev-parse HEAD~1 >/dev/null 2>&1; then
        RESOLVED_BASE=$(git rev-parse HEAD~1)
    else
        RESOLVED_BASE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    fi
else
    RESOLVED_BASE="$BASE_SHA"
fi

echo "[detect-layers] RESOLVED_BASE=${RESOLVED_BASE}"

filter_layers() {
    local json="$1"
    # Fallback to empty array if JSON is invalid or null
    if [[ -z "$json" ]] || [[ "$json" == "null" ]]; then json="[]"; fi
    jq -c --argjson exclude "${EXCLUDE_LAYERS:-[]}" '
        map(select((. as $layer | ($exclude | index($layer))) | not))
    ' <<< "$json"
}

# --- EXECUTION ---
# 1. Handle Manual Overrides
if [[ "$EVENT_NAME" == "workflow_dispatch" && -n "$MANUAL_LAYER" ]]; then
    CLEAN_LAYER="${MANUAL_LAYER#live/}"
    layers_json="[\"${CLEAN_LAYER}\"]"
else
    # 2. Auto-Detect via deploy.sh (uses git diff between RESOLVED_BASE and HEAD_SHA)
    layers_json="$(bash .github/scripts/deploy.sh detect-layers "${RESOLVED_BASE}" "${HEAD_SHA}" || echo "[]")"
fi

# 3. Apply Weighted Sorting (Networking -> IAM -> Data -> LiteLLM -> Agents)
ORDERED_JSON=$(echo "${layers_json:-[]}" | jq -c 'if type == "array" then sort_by(
    if contains("networking") then 1
    elif contains("iam") then 2
    elif (contains("rds") or contains("redis") or contains("elasticache")) then 3
    elif contains("litellm") then 5
    elif contains("agents") then 6
    else 9 end
) | unique else [] end')

filtered="$(filter_layers "$ORDERED_JSON")"

# 4. Determine Docker Folders
if [[ "$EVENT_NAME" == "workflow_dispatch" && -n "$DOCKER_FOLDER" ]]; then
    # Use explicit folder from UI, but normalize to an existing path.
    # Most repo paths are under `live/`, while users often input `production/litellm`.
    if [[ -d "$DOCKER_FOLDER" ]]; then
        NORMALIZED_DOCKER_FOLDER="$DOCKER_FOLDER"
    elif [[ -d "live/$DOCKER_FOLDER" ]]; then
        NORMALIZED_DOCKER_FOLDER="live/$DOCKER_FOLDER"
    else
        # Keep as-is; the downstream build step will fail with a clear error.
        NORMALIZED_DOCKER_FOLDER="$DOCKER_FOLDER"
        echo "[detect-layers] WARNING: docker_folder '$DOCKER_FOLDER' not found (also tried 'live/$DOCKER_FOLDER')"
    fi

    folders_json=$(jq -nc --arg f "$NORMALIZED_DOCKER_FOLDER" '[$f]')
elif [[ "$EVENT_NAME" == "workflow_dispatch" && "$FORCE_DOCKER" == "true" ]]; then
    # Force build all potential targets
    folders_json=$(find live -maxdepth 3 -name 'Dockerfile' -o -name '.postbuild.sh' | awk -F'/' '{print $1"/"$2"/"$3}' | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
else
    # Auto-infer from changed layers
    folders_json=$(echo "$filtered" | jq -c 'map("live/" + (split("/") | .[0:2] | join("/"))) | unique')
fi

# 5. Emit Final Results
emit_output "layers" "$filtered"
emit_output "folders" "$folders_json"
emit_output "has_changes" "$([[ "$filtered" != "[]" || "$folders_json" != "[]" ]] && echo "1" || echo "0")"
emit_output "base_sha" "$RESOLVED_BASE"
emit_output "head_sha" "$HEAD_SHA"