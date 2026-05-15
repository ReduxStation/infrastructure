#!/bin/bash
# Poll the running DreamDaemon every POLL_INTERVAL seconds and refresh
# serverinfo.json so the public-log-parser can hide the active round.
set -u
while true; do
    php /app/update.php || echo "[serverinfo] update.php exited non-zero" >&2
    sleep "${POLL_INTERVAL:-30}"
done
