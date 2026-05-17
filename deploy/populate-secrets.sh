#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../globals.env"

sudo mkdir -p "${SECRETS_DIR}"

prompt_secret() {
    local name="$1"
    local prompt="$2"
    if [ -r "${SECRETS_DIR}/${name}" ]; then
        echo "${name}: already present, skipping"
        return
    fi
    echo -n "Enter ${prompt}: "
    read -rs val
    echo
    echo -n "${val}" | sudo tee "${SECRETS_DIR}/${name}" >/dev/null
    sudo chmod 0400 "${SECRETS_DIR}/${name}"
    sudo chown root:root "${SECRETS_DIR}/${name}"
    echo "${name}: stored"
}

prompt_secret mysql_root_password "MariaDB root password"
prompt_secret mysql_password "MariaDB ss13 user password"
prompt_secret comms "comms.txt content (chat tokens, COMMS_KEY, etc.)"
prompt_secret dbconfig "dbconfig.txt content (DB connection details with password)"
prompt_secret webhooks "webhooks.txt content (or empty if unused)"
prompt_secret tts_secrets "tts_secrets.txt content (or empty if unused)"

echo "populate-secrets: done"
