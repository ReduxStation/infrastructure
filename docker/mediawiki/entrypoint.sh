#!/usr/bin/env bash
# Wrapper around mediawiki:1.42's default startup. On first start the
# container has no database schema and no LocalSettings.php in /var/www/html/
# (we bind-mount it but install.php expects to *generate* one). To keep
# install.php happy AND keep our bind-mounted config authoritative, we:
#
#   1. Wait for MariaDB to be reachable.
#   2. If `/var/www/html/.redux-installed` is missing, run install.php
#      against a throwaway file path, then delete that file. install.php
#      writes the DB schema + initial admin row as a side effect, which
#      is what we actually want.
#   3. Drop /var/www/html/LocalSettings.php in place (it's the bind mount
#      target — already present, but make sure ownership matches Apache).
#   4. Run any pending maintenance/update.php on every start so MW schema
#      stays current across image bumps.
#   5. exec apache2-foreground.
#
# Required env vars:
#   MEDIAWIKI_DB_HOST       e.g. mariadb
#   MEDIAWIKI_DB_NAME       e.g. mediawiki
#   MEDIAWIKI_DB_USER       e.g. ss13 (must be granted on the DB)
#   MEDIAWIKI_DB_PASSWORD   matches mariadb's MYSQL_PASSWORD secret
#   MEDIAWIKI_ADMIN_USER    initial sysop username
#   MEDIAWIKI_ADMIN_PASSWORD initial sysop password (first start only)
#   MEDIAWIKI_SITENAME      e.g. ReduxStation Wiki
#   MEDIAWIKI_SERVER        e.g. https://wiki.reduxstation.com

set -euo pipefail

require_env() {
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            echo "[redux-mw] missing env var: $var" >&2
            exit 1
        fi
    done
}

require_env \
    MEDIAWIKI_DB_HOST MEDIAWIKI_DB_NAME MEDIAWIKI_DB_USER MEDIAWIKI_DB_PASSWORD \
    MEDIAWIKI_ADMIN_USER MEDIAWIKI_ADMIN_PASSWORD \
    MEDIAWIKI_SITENAME MEDIAWIKI_SERVER

# Wait for MariaDB. Healthcheck on the mariadb service already gates this,
# but a short poll here keeps logs readable on dev / replay-from-snapshot.
echo "[redux-mw] waiting for ${MEDIAWIKI_DB_HOST}:3306..."
for i in $(seq 1 60); do
    if nc -z "${MEDIAWIKI_DB_HOST}" 3306 2>/dev/null; then
        echo "[redux-mw] MariaDB reachable after ${i}s."
        break
    fi
    sleep 1
done

# Our LocalSettings.php is bind-mounted at /opt/redux-mw/LocalSettings.php
# (NOT /var/www/html/LocalSettings.php). install.php refuses to run if
# a LocalSettings.php already exists in /var/www/html, so we keep ours
# out of the way during install and copy it in after.
SRC_LOCAL_SETTINGS=/opt/redux-mw/LocalSettings.php
DST_LOCAL_SETTINGS=/var/www/html/LocalSettings.php

if [ ! -f "${SRC_LOCAL_SETTINGS}" ]; then
    echo "[redux-mw] ${SRC_LOCAL_SETTINGS} missing — bind mount not wired?" >&2
    exit 1
fi

INSTALL_MARKER=/var/www/html/images/.redux-installed
if [ ! -f "${INSTALL_MARKER}" ]; then
    echo "[redux-mw] first-run install: schema + initial admin"
    # Make sure no stale LocalSettings.php is in place from a prior aborted
    # install — install.php will refuse otherwise.
    rm -f "${DST_LOCAL_SETTINGS}"
    php /var/www/html/maintenance/install.php \
        --confpath=/tmp \
        --dbtype=mysql \
        --dbserver="${MEDIAWIKI_DB_HOST}" \
        --dbname="${MEDIAWIKI_DB_NAME}" \
        --dbuser="${MEDIAWIKI_DB_USER}" \
        --dbpass="${MEDIAWIKI_DB_PASSWORD}" \
        --installdbuser="${MEDIAWIKI_DB_USER}" \
        --installdbpass="${MEDIAWIKI_DB_PASSWORD}" \
        --scriptpath= \
        --server="${MEDIAWIKI_SERVER}" \
        --lang=en \
        --pass="${MEDIAWIKI_ADMIN_PASSWORD}" \
        --skins=Vector \
        "${MEDIAWIKI_SITENAME}" \
        "${MEDIAWIKI_ADMIN_USER}"
    # The install.php-generated LocalSettings.php at /tmp/LocalSettings.php
    # is unused; our bind-mounted one is the authoritative config.
    rm -f /tmp/LocalSettings.php
    mkdir -p /var/www/html/images
    chown -R www-data:www-data /var/www/html/images
    touch "${INSTALL_MARKER}"
else
    echo "[redux-mw] already installed, skipping schema setup"
fi

# Copy LocalSettings.php into the wiki root on every start so config
# changes in the bind-mount source propagate. cp -p preserves perms;
# the source is mode 0644 in the image build.
cp "${SRC_LOCAL_SETTINGS}" "${DST_LOCAL_SETTINGS}"
chown www-data:www-data "${DST_LOCAL_SETTINGS}"
chmod 644 "${DST_LOCAL_SETTINGS}"

# Apply schema migrations on every start. Idempotent; safe on a fresh DB.
echo "[redux-mw] running maintenance/update.php"
php /var/www/html/maintenance/update.php --quick --quiet

# Owner adjustments for the images/ volume so uploads survive.
chown -R www-data:www-data /var/www/html/images

echo "[redux-mw] handing off to apache"
exec "$@"
