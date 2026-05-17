#!/usr/bin/env bash
set -euo pipefail
# Runs before each compile. Sync config so the compiled deploy sees fresh content.
exec "$(dirname "$0")/update-config.sh"
