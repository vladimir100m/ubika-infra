#!/usr/bin/env bash
set -euo pipefail

# Usage: .github/scripts/prebuild-check.sh <layer>
#
# 1. Checks if .prebuild.sh exists in the layer directory and runs it if present.
# 2. Checks if any Terraform files (*.tf) changed in the layer and sets a flag.
#
# Outputs:
#   - "TF_CHANGED=1" if any .tf file changed, else "TF_CHANGED=0"

LAYER_DIR="$1"

cd "$LAYER_DIR"

if [[ -f .prebuild.sh ]]; then
  echo "Found .prebuild.sh in $LAYER_DIR, executing..."
  chmod +x .prebuild.sh
  ./\.prebuild.sh
else
  echo "No .prebuild.sh found in $LAYER_DIR."
fi

# Check for changed Terraform files (relative to main branch)
TF_CHANGED=0
if git diff --name-only origin/main...HEAD | grep -E '\.tf$' | grep -q "^$LAYER_DIR/"; then
  TF_CHANGED=1
fi

echo "TF_CHANGED=$TF_CHANGED"
