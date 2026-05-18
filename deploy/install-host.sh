#!/usr/bin/env bash
# Idempotent host setup. Run after every git pull from this repo.
set -euo pipefail
. "$(dirname "$0")/../globals.env"

# Dirs
sudo mkdir -p "${TGS_EVENTSCRIPTS_DIR}" "${SECRETS_DIR}" /srv/redux
sudo chown root:root "${SECRETS_DIR}"
sudo chmod 755 "${SECRETS_DIR}"

# Pre-create external volumes (one-time, idempotent)
for vol in tgs_instances mariadb_data caddy_data caddy_certs \
           webmap_tiles webmap_site_dist demo_viewer_dist website_dist \
           tgs_logs; do
    docker volume inspect "reduxstation_${vol}" >/dev/null 2>&1 || \
        docker volume create "reduxstation_${vol}"
done

# Build .env from globals.env + .env.local (compose reads .env)
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
if [ -L "$INFRA/.env" ]; then rm "$INFRA/.env"; fi
{
    cat "$INFRA/globals.env"
    if [ -f "$INFRA/.env.local" ]; then
        echo ""
        echo "# --- .env.local overrides ---"
        cat "$INFRA/.env.local"
    fi
} > "$INFRA/.env"
chmod 600 "$INFRA/.env"

# Apply sysctl
sudo cp "$INFRA/sysctl.d/99-bbr.conf" /etc/sysctl.d/
sudo /usr/sbin/sysctl --system >/dev/null

echo "install-host: done"
