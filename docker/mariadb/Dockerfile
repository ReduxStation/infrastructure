FROM mariadb:10.11

# ── SQL schemas baked into the image ─────────────────────────────────────────
# Pulled from sibling repos via BuildKit additional_contexts declared
# in docker-compose.yml (`game=../game` and `infra=..`).
COPY --from=game SQL/tgstation_schema_prefixed.sql /docker-entrypoint-schemas/tgstation_schema_prefixed.sql
COPY --from=infra slimbus/sql/alt_db.sql           /docker-entrypoint-schemas/alt_db.sql
COPY --from=game hippiestation/SQL/mentor.sql      /docker-entrypoint-schemas/mentor.sql
COPY --from=game hippiestation/SQL/donator.sql     /docker-entrypoint-schemas/donator.sql
COPY --from=game hippiestation/SQL/brdetector.sql  /docker-entrypoint-schemas/brdetector.sql

# ── Init script ───────────────────────────────────────────────────────────────
COPY --from=infra docker/mysql-init/01-init.sh /docker-entrypoint-initdb.d/01-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/01-init.sh
