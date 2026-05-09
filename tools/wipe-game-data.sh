#!/usr/bin/env bash
# Wipe all game data and round logs, leaving the TGS server's own state
# intact. Run on the live host as the docker-capable user.
#
# What gets wiped:
#   * Every round log under the game_data volume's logs/ tree.
#   * The serverinfo.json marker file (reset to {"servers":[]}).
#   * The ss13 database (game state: bans, donor list, mentor list,
#     br-detector, all round records).
#   * The statbus database (slimbus alt_db).
#
# What is preserved:
#   * The tgs database (TGS server config, deployment job history,
#     panel users). Wiping this would force a fresh TGS first-run.
#   * The mysql system schema.
#
# Pre-flight: STOP THE WATCHDOG from the TGS panel before running.
# Otherwise the game writes to ss13 mid-wipe and the schema reload
# races with active connections.
#
# Post-flight: START THE WATCHDOG from the panel. The first round will
# come up on a fresh DB and a brand-new log tree.

set -euo pipefail

CONFIRM="${1:-}"
if [[ "$CONFIRM" != "--yes-i-mean-it" ]]; then
  cat <<'USAGE'
This script DELETES the game database and all round logs.
Pass --yes-i-mean-it to acknowledge:

  ./tools/wipe-game-data.sh --yes-i-mean-it

Make sure the watchdog is stopped on the TGS panel first.
USAGE
  exit 1
fi

# Find the running mariadb container by name pattern. Works regardless
# of which compose plugin (V1 docker-compose vs V2 docker compose) the
# host happens to have installed.
MARIADB="$(docker ps --filter "name=mariadb" --format '{{.Names}}' | head -1)"
if [[ -z "$MARIADB" ]]; then
  echo "ERROR: no running container with 'mariadb' in its name." >&2
  exit 1
fi
echo "Targeting mariadb container: $MARIADB"

# Find the game_data volume by name pattern. Same compose-version-agnostic
# approach. Falls back to the canonical name if the pattern misses.
GAME_VOL="$(docker volume ls --filter "name=game_data" --format '{{.Name}}' | head -1)"
if [[ -z "$GAME_VOL" ]]; then
  GAME_VOL="resurgencestation_game_data"
fi
echo "Targeting game_data volume: $GAME_VOL"

# 1. Logs and the serverinfo.json marker.
echo "Wiping logs and serverinfo.json..."
docker run --rm -v "$GAME_VOL:/v" alpine sh -c \
  'rm -rf /v/logs/* && printf "%s" "{\"servers\":[]}" > /v/serverinfo.json'

# 2. Drop and recreate the game databases. tgs is intentionally untouched.
echo "Dropping and recreating ss13 + statbus..."
docker exec -i "$MARIADB" sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD"' <<'SQL'
DROP DATABASE IF EXISTS ss13;
DROP DATABASE IF EXISTS statbus;
CREATE DATABASE ss13    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE statbus CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON ss13.*    TO 'ss13'@'%';
GRANT ALL PRIVILEGES ON statbus.* TO 'ss13'@'%';
FLUSH PRIVILEGES;
SQL

# 3. Reload schemas. The .sql files are baked into the mariadb image at
# /docker-entrypoint-schemas (see docker/mariadb/Dockerfile), so we do
# not need any host-side files.
for f in tgstation_schema_prefixed.sql mentor.sql donator.sql brdetector.sql; do
  echo "Loading $f into ss13..."
  docker exec "$MARIADB" sh -c \
    "mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" ss13 < /docker-entrypoint-schemas/$f"
done

echo "Loading alt_db.sql into statbus..."
docker exec "$MARIADB" sh -c \
  'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" statbus < /docker-entrypoint-schemas/alt_db.sql'

echo
echo "WIPE DONE."
echo "Now start the watchdog from the TGS panel."
