#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"

# ---------------------------------------------------------------------------
# resolve_dir <layer>
#
# Maps a layer name (relative path inside live/) to its filesystem directory.
# Examples:
#   _global                   → live/_global
#   production/networking     → live/production/networking
#   production/clusters/api   → live/production/clusters/api
# ---------------------------------------------------------------------------
resolve_dir() {
  local layer="$1"
  echo "live/$layer"
}

# ---------------------------------------------------------------------------
# detect_layers <base_sha> <head_sha>
#
# Outputs a JSON array of layer names whose files changed between the two
# commits.  A "layer" is the relative path (inside live/) to the deepest
# directory that contains a providers.tf.  Only directories that actually
# have a providers.tf are emitted.
# ---------------------------------------------------------------------------
detect_layers() {
  local base_sha="$1"
  local head_sha="$2"

  if [[ -z "$base_sha" || "$base_sha" == "0000000000000000000000000000000000000000" ]]; then
    base_sha="$(git rev-parse "${head_sha}^" 2>/dev/null || true)"
  fi

  if [[ -z "$base_sha" ]]; then
    # No base commit (first push): deploy every layer that exists.
    find live -name providers.tf -exec dirname {} \; \
      | sed 's|^live/||' \
      | sort -u \
      | jq -R -s -c 'split("\n") | map(select(length>0))'
    return 0
  fi

  local changed_files
  changed_files="$(git diff --name-only "$base_sha" "$head_sha" | grep '^live/' || true)"

  if [[ -z "$changed_files" ]]; then
    echo '[]'
    return 0
  fi

  local -a layers=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local dir="${file%/*}"
    # Walk up from the file's directory toward live/ and find the deepest
    # ancestor that has a providers.tf – that directory is the owning layer.
    local check="$dir"
    local found_layer=""
    while [[ "$check" != "live" && "$check" != "." && -n "$check" ]]; do
      if [[ -f "$check/providers.tf" ]]; then
        found_layer="${check#live/}"
        break
      fi
      check="${check%/*}"
    done

    if [[ -n "$found_layer" ]]; then
      layers+=("$found_layer")
      continue
    fi

    while [[ "$dir" != "." && -n "$dir" ]]; do
      while IFS= read -r descendant_provider; do
        [[ -z "$descendant_provider" ]] && continue
        layers+=("${descendant_provider#live/}")
      done < <(find "$dir" -name providers.tf -exec dirname {} \; 2>/dev/null | sort -u)

      [[ "$dir" == "live" ]] && break
      dir="${dir%/*}"
    done
  done <<< "$changed_files"

  printf '%s\n' "${layers[@]}" | awk 'NF' | sort -u | jq -R -s -c 'split("\n") | map(select(length>0))'
}

terraform_validate() {
  local layer="$1"
  local dir
  dir="$(resolve_dir "$layer")"

  terraform -chdir="$dir" init -input=false -reconfigure -backend-config=backend.hcl
  terraform -chdir="$dir" fmt -check -recursive
  terraform -chdir="$dir" validate
}

terraform_plan() {
  local layer="$1"
  local dir
  dir="$(resolve_dir "$layer")"

  terraform -chdir="$dir" init -input=false -reconfigure -backend-config=backend.hcl
  terraform -chdir="$dir" fmt -check -recursive
  terraform -chdir="$dir" validate
  terraform -chdir="$dir" plan -no-color -input=false -out=tfplan
}

terraform_apply() {
  local layer="$1"
  local dir
  dir="$(resolve_dir "$layer")"

  terraform -chdir="$dir" init -input=false -reconfigure -backend-config=backend.hcl
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
  terraform_validate)
    terraform_validate "${2:-}"
    ;;
  *)
    echo "Usage: $0 {detect-layers <base_sha> <head_sha>|resolve-dir <layer>|terraform-plan <layer>|terraform-apply <layer>}" >&2
    exit 1
    ;;
esac
