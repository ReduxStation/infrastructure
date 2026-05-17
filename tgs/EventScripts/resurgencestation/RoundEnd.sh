#!/bin/bash
# TGS event script invoked when the game emits TgsTriggerEvent("RoundEnd", ...)
# from code/controllers/subsystem/dbcore.dm::SetRoundEnd after the round's
# end_datetime is recorded.
#
# Clears the active-round list in serverinfo.json so the public-log-parser
# stops hiding this round's directory at logs.owo.fm.
#
# TGS6 invokes custom event scripts as:
#   <script> <game_dir> <param1> <param2> ...
# DMAPI call: world.TgsTriggerEvent("RoundEnd", list("[GLOB.round_id]")) so:
#   $1 = game directory (Game/Live)
#   $2 = round_id as a string (informational only; we always clear)
#
# $1/data/ resolves through TGS-6's GameStaticFiles hard-link back to the
# persistent volume mounted at Configuration/GameStaticFiles/data. Caddy
# reads the same volume from /srv/logs and serves serverinfo.json to the
# public-log-parser.
set -euo pipefail

GAME_DIR="${1:-}"
if [ -z "$GAME_DIR" ]; then
  echo "RoundEnd: no game dir passed in arg 1, doing nothing" >&2
  exit 0
fi

OUT="$GAME_DIR/data/serverinfo.json"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'JSON'
{"servers":[]}
JSON
echo "RoundEnd: cleared ${OUT} (round ${2:-unknown} ended)"
