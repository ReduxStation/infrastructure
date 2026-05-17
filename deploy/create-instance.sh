#!/usr/bin/env bash
# Creates TGS instance after fresh deploy. Stub for Phase 6.
# TGS_USERNAME, TGS_PASSWORD must be available in env.
set -euo pipefail
. "$(dirname "$0")/../globals.env"

: "${TGS_URL:?set TGS_URL env}"
: "${TGS_USERNAME:?set TGS_USERNAME env}"
: "${TGS_PASSWORD:?set TGS_PASSWORD env}"
: "${TGS_API_VERSION:=10.14.1}"

# This is a Phase 6 helper, fleshed out at cutover time. Stub for now.
echo "create-instance: stub. Implement at Phase 6."
exit 0
