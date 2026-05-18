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

# install.php emits a LocalSettings.php to its --target path. We never use
# that file; the bind-mounted one in /var/www/html/LocalSettings.php is the
# real config. install.php's side effect — writing the DB schema and the
# initial sysop row — is what we want.
INSTALL_MARKER=/var/www/html/images/.redux-installed
if [ ! -f "${INSTALL_MARKER}" ]; then
    echo "[redux-mw] first-run install: schema + initial admin"
    php /var/www/html/maintenance/install.php \
        --confpath=/tmp/redux-mw-install \
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
    rm -f /tmp/redux-mw-install
    mkdir -p /var/www/html/images
    touch "${INSTALL_MARKER}"
    chown -R www-data:www-data /var/www/html/images
else
    echo "[redux-mw] already installed, skipping schema setup"
fi

# Apply schema migrations on every start. Idempotent; safe on a fresh DB.
echo "[redux-mw] running maintenance/update.php"
php /var/www/html/maintenance/update.php --quick --quiet

# LocalSettings.php is bind-mounted read-only at /var/www/html/LocalSettings.php.
# Make sure the file is what we expect before Apache picks it up.
if [ ! -f /var/www/html/LocalSettings.php ]; then
    echo "[redux-mw] LocalSettings.php missing — bind mount not wired?" >&2
    exit 1
fi

# Owner adjustments for the images/ volume so uploads survive.
chown -R www-data:www-data /var/www/html/images

echo "[redux-mw] handing off to apache"
exec "$@"
