#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../globals.env"

sudo mkdir -p "${TGS_EVENTSCRIPTS_DIR}" "${SECRETS_DIR}" /srv/resurgence
sudo chown root:root "${SECRETS_DIR}"
sudo chmod 755 "${SECRETS_DIR}"

# Pre-create external volumes (one-time)
for vol in tgs_instances mariadb_data caddy_data caddy_certs \
           webmap_tiles webmap_site_dist demo_viewer_dist tgs_logs; do
    docker volume inspect "resurgencestation_${vol}" >/dev/null 2>&1 || \
        docker volume create "resurgencestation_${vol}"
done

# Apply sysctl
sudo cp "$(dirname "$0")/../sysctl.d/99-bbr.conf" /etc/sysctl.d/
sudo sysctl --system >/dev/null
echo "install-host: done"
