#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"

resolve_dir() {
  local layer="$1"
  if [[ "$layer" == "root" ]]; then
    echo "infra"
  else
    echo "infra/$layer"
  fi
}

detect_layers() {
  local base_sha="$1"
  local head_sha="$2"

  if [[ -z "$base_sha" || "$base_sha" == "0000000000000000000000000000000000000000" ]]; then
    base_sha="$(git rev-parse "${head_sha}^" 2>/dev/null || true)"
  fi

  if [[ -z "$base_sha" ]]; then
    echo '["root"]'
    return 0
  fi

  local changed_files
  changed_files="$(git diff --name-only "$base_sha" "$head_sha" | grep '^infra/' || true)"

  if [[ -z "$changed_files" ]]; then
    echo '[]'
    return 0
  fi

  local -a layers=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local rel="${file#infra/}"
    if [[ "$rel" == */* ]]; then
      layers+=("${rel%%/*}")
    else
      layers+=("root")
    fi
  done <<< "$changed_files"

  local unique_layers
  unique_layers="$(printf '%s\n' "${layers[@]}" | awk 'NF' | sort -u)"

  local -a deploy_layers=()
  while IFS= read -r layer; do
    [[ -z "$layer" ]] && continue
    local dir
    dir="$(resolve_dir "$layer")"
    if [[ -d "$dir" ]] && compgen -G "$dir/*.tf" > /dev/null; then
      deploy_layers+=("$layer")
    fi
  done <<< "$unique_layers"

  printf '%s\n' "${deploy_layers[@]}" | awk 'NF' | sort -u | jq -R -s -c 'split("\n") | map(select(length>0))'
}

terraform_plan() {
  local layer="$1"
  local dir
  dir="$(resolve_dir "$layer")"

  terraform -chdir="$dir" init -input=false
  terraform -chdir="$dir" fmt -check -recursive
  terraform -chdir="$dir" validate
  terraform -chdir="$dir" plan -no-color -input=false -out=tfplan
}

terraform_apply() {
  local layer="$1"
  local dir
  dir="$(resolve_dir "$layer")"

  terraform -chdir="$dir" apply -auto-approve -input=false tfplan
}

case "$cmd" in
  detect-layers)
    detect_layers "${2:-}" "${3:-}"
    ;;
  resolve-dir)
    resolve_dir "${2:-}"
    ;;
  terraform-plan)
    terraform_plan "${2:-}"
    ;;
  terraform-apply)
    terraform_apply "${2:-}"
    ;;
  *)
    echo "Usage: $0 {detect-layers <base_sha> <head_sha>|resolve-dir <layer>|terraform-plan <layer>|terraform-apply <layer>}" >&2
    exit 1
    ;;
esac
