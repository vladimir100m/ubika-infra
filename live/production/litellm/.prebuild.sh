#!/usr/bin/env bash
set -euo pipefail

echo ".prebuild.sh is deprecated. Running .postbuild.sh instead."
exec ./.postbuild.sh
