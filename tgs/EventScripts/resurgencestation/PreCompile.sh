#!/usr/bin/env bash
set -euo pipefail
# Runs before each compile. Sync config so the compiled deploy sees fresh content.
exec "${TGS_INSTANCE_ROOT}/Configuration/EventScripts/update-config.sh"
