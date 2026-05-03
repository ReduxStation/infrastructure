#!/bin/bash
# Runs once on first container start (when /var/lib/mysql is empty).
# Creates the statbus alt-database, grants the ss13 user access to it,
# then loads every schema into the correct database.
set -euo pipefail

SCHEMA=/docker-entrypoint-schemas

# ── Create statbus database and grant the game user access ────────────────────
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS statbus
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON statbus.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# ── Load tgstation game schema ────────────────────────────────────────────────
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" ss13 \
    < "${SCHEMA}/tgstation_schema_prefixed.sql"

# ── Load HippieStation extras into ss13 ──────────────────────────────────────
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" ss13 \
    < "${SCHEMA}/mentor.sql"

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" ss13 \
    < "${SCHEMA}/donator.sql"

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" ss13 \
    < "${SCHEMA}/brdetector.sql"

# ── Load statbus/slimbus schema ───────────────────────────────────────────────
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" statbus \
    < "${SCHEMA}/alt_db.sql"

echo "All schemas loaded successfully."
