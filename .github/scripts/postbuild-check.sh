#!/usr/bin/env bash
set -euo pipefail

# Usage: .github/scripts/postbuild-check.sh <layer_dir>
#
# Walks from the layer directory up to live/ and executes any `.postbuild.sh`
# files it finds, starting from the highest matching parent.
#
# Outputs:
#   - "ARCH=x86|arm" (defaults to x86 when not provided by scripts)

LAYER_DIR="$1"
ARCH="x86"

run_postbuild_scripts() {
  local current_dir="$LAYER_DIR"
  local -a script_dirs=()

  while [[ "$current_dir" != "." && -n "$current_dir" ]]; do
    if [[ -f "$current_dir/.postbuild.sh" ]]; then
      script_dirs+=("$current_dir")
    fi

    [[ "$current_dir" == "live" ]] && break
    current_dir="${current_dir%/*}"
  done

  if [[ ${#script_dirs[@]} -eq 0 ]]; then
    echo "No .postbuild.sh found for $LAYER_DIR."
    return
  fi

  for (( index=${#script_dirs[@]} - 1; index>=0; index-- )); do
    local script_dir="${script_dirs[$index]}"
    local script_output
    local script_arch

    echo "Found .postbuild.sh in $script_dir, executing..."
    script_output="$(
      cd "$script_dir"
      chmod +x .postbuild.sh
      ./.postbuild.sh
    )"

    printf '%s\n' "$script_output"

    script_arch="$(printf '%s\n' "$script_output" | grep -E '^ARCH=' | tail -n1 | cut -d'=' -f2 | xargs || true)"
    if [[ -n "$script_arch" ]]; then
      ARCH="$script_arch"
    fi
  done
}

run_postbuild_scripts

echo "ARCH=${ARCH}"
