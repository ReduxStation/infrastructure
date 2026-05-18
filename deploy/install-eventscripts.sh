#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../globals.env"

SRC="$(dirname "$0")/../tgs/EventScripts/reduxstation"
sudo mkdir -p "${TGS_EVENTSCRIPTS_DIR}"
sudo cp -f "${SRC}"/*.sh "${TGS_EVENTSCRIPTS_DIR}/"
sudo cp -f "$(dirname "$0")/../globals.env" "${TGS_EVENTSCRIPTS_DIR}/"
sudo chown -R root:root "${TGS_EVENTSCRIPTS_DIR}"
sudo chmod 755 "${TGS_EVENTSCRIPTS_DIR}"
sudo chmod 755 "${TGS_EVENTSCRIPTS_DIR}"/*.sh
sudo chmod 644 "${TGS_EVENTSCRIPTS_DIR}/globals.env"
echo "install-eventscripts: populated ${TGS_EVENTSCRIPTS_DIR}"
