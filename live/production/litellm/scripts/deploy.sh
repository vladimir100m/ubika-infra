#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/deploy.sh <command> [args...]
# Commands:
#   terraform-plan <layer>
#   terraform-apply <layer>
#   resolve-dir <layer>

COMMAND="${1:-}"
LAYER="${2:-}"

case "$COMMAND" in
  terraform-plan)
    terraform -chdir="$LAYER" plan -out=tfplan
    ;;
  terraform-apply)
    terraform -chdir="$LAYER" apply tfplan
    ;;
  resolve-dir)
    # This is a placeholder for resolving a layer directory
    # In your workflow, this is used to map a layer name to a directory path
    echo "live/${LAYER}"
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: scripts/deploy.sh <terraform-plan|terraform-apply|resolve-dir> <layer>"
    exit 1
    ;;
esac
