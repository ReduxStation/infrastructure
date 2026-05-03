#!/bin/bash
# Statbus (slimbus) entrypoint.
# Generates /var/www/html/.env from Docker environment variables so
# phpdotenv can find the credentials, then execs php-fpm.
set -euo pipefail

cat > /var/www/html/.env <<EOF
DB_METHOD=${DB_METHOD:-mysql}
DB_DATABASE=${DB_DATABASE:-ss13}
DB_USERNAME=${DB_USERNAME:-ss13}
DB_PASSWORD=${DB_PASSWORD:?DB_PASSWORD is required}
DB_HOST=${DB_HOST:-mariadb}
DB_PORT=${DB_PORT:-3306}
DB_PREFIX=${DB_PREFIX:-SS13_}

ALT_DB_METHOD=${ALT_DB_METHOD:-mysql}
ALT_DB_DATABASE=${ALT_DB_DATABASE:-statbus}
ALT_DB_USERNAME=${ALT_DB_USERNAME:-ss13}
ALT_DB_PASSWORD=${ALT_DB_PASSWORD:-${DB_PASSWORD}}
ALT_DB_HOST=${ALT_DB_HOST:-mariadb}
ALT_DB_PORT=${ALT_DB_PORT:-3306}

APP="${APP:-HippieStation Statbus}"
GITHUB="${GITHUB:-HippieStation/HippieStation}"
DEBUG="${DEBUG:-FALSE}"
DISPLAY_ERRORS="${DISPLAY_ERRORS:-FALSE}"
EOF

chown www-data:www-data /var/www/html/.env

exec "$@"
