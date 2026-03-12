#!/usr/bin/env bash
set -euo pipefail

# Usage: .github/scripts/prebuild-check.sh <layer_dir> [base_sha] [head_sha]
#
# 1. Walks from the layer directory up to live/ and executes any `.prebuild.sh`
#    files it finds, starting from the highest matching parent.
# 2. Checks if any Terraform files (*.tf) changed in the layer and sets a flag.
#
# Outputs:
#   - "TF_CHANGED=1" if any .tf file changed, else "TF_CHANGED=0"

LAYER_DIR="$1"
BASE_SHA="${2:-}"
HEAD_SHA="${3:-}"

run_prebuild_scripts() {
  local current_dir="$LAYER_DIR"
  local -a script_dirs=()

  while [[ "$current_dir" != "." && -n "$current_dir" ]]; do
    if [[ -f "$current_dir/.prebuild.sh" ]]; then
      script_dirs+=("$current_dir")
    fi

    [[ "$current_dir" == "live" ]] && break
    current_dir="${current_dir%/*}"
  done

  if [[ ${#script_dirs[@]} -eq 0 ]]; then
    echo "No .prebuild.sh found for $LAYER_DIR."
    return
  fi

  for (( index=${#script_dirs[@]} - 1; index>=0; index-- )); do
    local script_dir="${script_dirs[$index]}"
    echo "Found .prebuild.sh in $script_dir, executing..."
    (
      cd "$script_dir"
      chmod +x .prebuild.sh
      ./.prebuild.sh
    )
  done
}

run_prebuild_scripts

TF_CHANGED=0
FORCE_DEPLOY=0

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  TF_CHANGED=1
elif git diff --name-only "$BASE_SHA" "$HEAD_SHA" | grep -E "^${LAYER_DIR}/.*\.tf$" >/dev/null; then
  TF_CHANGED=1
fi

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  FORCE_DEPLOY=0
elif git diff --name-only "$BASE_SHA" "$HEAD_SHA" | grep -E "^${LAYER_DIR}/(force\.deploy|.prebuild\.sh)$" >/dev/null; then
  FORCE_DEPLOY=1
  TF_CHANGED=1
fi

echo "TF_CHANGED=$TF_CHANGED"
echo "FORCE_DEPLOY=$FORCE_DEPLOY"
echo "ARCH=${ARCH:-x86}"
