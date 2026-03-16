#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/deploy.sh <command> [args...]
# Commands:
#   detect-layers <base_sha> <head_sha>
#   terraform-init <layer>
#   terraform-plan <layer>
#   terraform-apply <layer>
#   resolve-dir <layer>

COMMAND="${1:-}"
LAYER="${2:-}"

resolve_layer_dir() {
  local layer_input="$1"

  if [[ -z "$layer_input" ]]; then
    echo ""
    return 0
  fi

  if [[ -d "$layer_input" ]]; then
    echo "$layer_input"
    return 0
  fi

  if [[ -d "live/$layer_input" ]]; then
    echo "live/$layer_input"
    return 0
  fi

  echo "$layer_input"
}

case "$COMMAND" in
  detect-layers)
    BASE_SHA="${2:-}"
    HEAD_SHA="${3:-}"

    is_valid_commit() {
      local sha="$1"
      [[ -n "$sha" ]] && git cat-file -e "${sha}^{commit}" 2>/dev/null
    }

    all_layers_json() {
      find live -type f -name main.tf -print \
        | sed 's|/main.tf$||' \
        | sed 's|^live/||' \
        | sort -u \
        | jq -R -s -c 'split("\n") | map(select(length > 0))'
    }

    nearest_layer_for_path() {
      local path="$1"
      local dir
      dir="$(dirname "$path")"

      while [[ "$dir" == live* && "$dir" != "live" ]]; do
        if [[ -f "$dir/main.tf" ]]; then
          echo "${dir#live/}"
          return 0
        fi
        dir="$(dirname "$dir")"
      done

      return 1
    }

    if ! is_valid_commit "$BASE_SHA" || ! is_valid_commit "$HEAD_SHA"; then
      all_layers_json
      exit 0
    fi

    CHANGED_FILES="$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")"

    if grep -q '^modules/' <<< "$CHANGED_FILES"; then
      all_layers_json
      exit 0
    fi

    LAYERS="$(
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ "$file" != live/* ]] && continue
        nearest_layer_for_path "$file" || true
      done <<< "$CHANGED_FILES" | sort -u
    )"

    if [[ -z "$LAYERS" ]]; then
      echo '[]'
    else
      printf '%s\n' "$LAYERS" | jq -R -s -c 'split("\n") | map(select(length > 0))'
    fi
    ;;
  terraform-init)
    LAYER_DIR="$(resolve_layer_dir "$LAYER")"
    if [[ -f "$LAYER_DIR/backend.hcl" ]]; then
      terraform -chdir="$LAYER_DIR" init -reconfigure -backend-config=backend.hcl -input=false
    else
      terraform -chdir="$LAYER_DIR" init -reconfigure -input=false
    fi
    ;;
  terraform-plan)
    LAYER_DIR="$(resolve_layer_dir "$LAYER")"
    terraform -chdir="$LAYER_DIR" plan -out=tfplan -input=false
    ;;
  terraform-apply)
    LAYER_DIR="$(resolve_layer_dir "$LAYER")"
    terraform -chdir="$LAYER_DIR" apply -auto-approve -input=false tfplan
    ;;
  resolve-dir)
    # This is a placeholder for resolving a layer directory
    # In your workflow, this is used to map a layer name to a directory path
    echo "live/${LAYER}"
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: scripts/deploy.sh <detect-layers|terraform-init|terraform-plan|terraform-apply|resolve-dir> <args>"
    exit 1
    ;;
esac
