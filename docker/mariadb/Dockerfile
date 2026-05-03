FROM mariadb:10.11

# ── SQL schemas baked into the image ─────────────────────────────────────────
# Stored under a separate directory so they don't collide with
# /docker-entrypoint-initdb.d scripts (which run in filename order).
COPY SQL/tgstation_schema_prefixed.sql  /docker-entrypoint-schemas/tgstation_schema_prefixed.sql
COPY slimbus/sql/alt_db.sql            /docker-entrypoint-schemas/alt_db.sql
COPY hippiestation/SQL/mentor.sql      /docker-entrypoint-schemas/mentor.sql
COPY hippiestation/SQL/donator.sql     /docker-entrypoint-schemas/donator.sql
COPY hippiestation/SQL/brdetector.sql  /docker-entrypoint-schemas/brdetector.sql

# ── Init script ───────────────────────────────────────────────────────────────
# MariaDB's entrypoint runs every *.sh / *.sql file in initdb.d on first start.
COPY docker/mysql-init/01-init.sh /docker-entrypoint-initdb.d/01-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/01-init.sh
