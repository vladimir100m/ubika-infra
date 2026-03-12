#!/usr/bin/env bash
set -euo pipefail

# Usage: .github/scripts/prebuild-check.sh <layer_dir> [base_sha] [head_sha]
#
# Checks if any Terraform files (*.tf) changed in the layer and sets a flag.
#
# Outputs:
#   - "TF_CHANGED=1" if any .tf file changed, else "TF_CHANGED=0"
#   - "FORCE_DEPLOY=1" if force marker files changed, else "FORCE_DEPLOY=0"

LAYER_DIR="$1"
BASE_SHA="${2:-}"
HEAD_SHA="${3:-}"
ARCH="x86"

is_valid_commit() {
  local sha="$1"
  [[ -n "$sha" ]] && git cat-file -e "${sha}^{commit}" 2>/dev/null
}

TF_CHANGED=0
FORCE_DEPLOY=1

if ! is_valid_commit "$BASE_SHA" || ! is_valid_commit "$HEAD_SHA"; then
  echo "[prebuild-check] warning: invalid BASE_SHA/HEAD_SHA, forcing TF_CHANGED=1"
  TF_CHANGED=1
elif git diff --name-only "$BASE_SHA" "$HEAD_SHA" | grep -E "^${LAYER_DIR}/.*\.tf$" >/dev/null; then
  TF_CHANGED=1
fi

if is_valid_commit "$BASE_SHA" && is_valid_commit "$HEAD_SHA"; then
  if git diff --name-only "$BASE_SHA" "$HEAD_SHA" | grep -E "^${LAYER_DIR}/(force\.deploy|\.postbuild\.sh)$" >/dev/null; then
    FORCE_DEPLOY=1
    TF_CHANGED=1
  fi
fi

case "${CPU_ARCHITECTURE:-$(uname -m)}" in
  x86|x86_64)
    ARCH="x86"
    ;;
  arm|arm64|aarch64)
    ARCH="arm"
    ;;
  *)
    ARCH="x86"
    ;;
esac

echo "[prebuild-check] LAYER_DIR=$LAYER_DIR"
echo "[prebuild-check] BASE_SHA=${BASE_SHA:-<empty>}"
echo "[prebuild-check] HEAD_SHA=${HEAD_SHA:-<empty>}"

echo "TF_CHANGED=$TF_CHANGED"
echo "FORCE_DEPLOY=$FORCE_DEPLOY"
echo "ARCH=$ARCH"
