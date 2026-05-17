#!/bin/bash
# TGS event script invoked when the game emits TgsTriggerEvent("RoundStart", ...)
# from code/controllers/subsystem/dbcore.dm::SetRoundID after the round_id is
# assigned by the database.
#
# Writes the active round id into a serverinfo.json file on the game_data
# volume. The public-log-parser polls this file via caddy:8081/serverinfo.json
# every 60 seconds and 404s any /YYYY/MM/DD/round-N/ path whose round_id is
# in the list, so the in-progress round stays hidden from logs.owo.fm.
#
# TGS6 invokes custom event scripts as:
#   <script> <game_dir> <param1> <param2> ...
# where <game_dir> is the active game directory (TGS prepends it) and the
# rest are the parameters from `world.TgsTriggerEvent("RoundStart", list(...))`.
# DMAPI call: world.TgsTriggerEvent("RoundStart", list("[GLOB.round_id]")) so:
#   $1 = game directory (Game/Live)
#   $2 = round_id as a string
#
# $1/data/ resolves through TGS-6's GameStaticFiles hard-link back to the
# persistent volume mounted at Configuration/GameStaticFiles/data. Caddy
# reads the same volume from /srv/logs and serves serverinfo.json to the
# public-log-parser.
set -euo pipefail

GAME_DIR="${1:-}"
ROUND_ID="${2:-}"
if [ -z "$GAME_DIR" ]; then
  echo "RoundStart: no game dir passed in arg 1, doing nothing" >&2
  exit 0
fi
if [ -z "$ROUND_ID" ]; then
  echo "RoundStart: no round_id passed in arg 2, doing nothing" >&2
  exit 0
fi

OUT="$GAME_DIR/data/serverinfo.json"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{"servers":[{"data":{"round_id":"${ROUND_ID}","identifier":"owo"}}]}
JSON
echo "RoundStart: wrote round_id ${ROUND_ID} to ${OUT}"
