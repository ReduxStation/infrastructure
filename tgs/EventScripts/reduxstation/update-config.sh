#!/usr/bin/env bash
set -euo pipefail
. /etc/tgs-EventScripts.d/reduxstation/globals.env
. "$(dirname "$0")/parse-server.sh"

TARGET="${TGS_INSTANCE_ROOT}/Configuration/GameStaticFiles/config"
SECRETS="${SECRETS_DIR}"

if [ ! -d "${TARGET}/.git" ]; then
    # Preserve untracked operator-managed media before re-init
    MEDIA_BAK=$(mktemp -d)
    for d in jukebox_music title_music title_screens reboot_themes; do
        [ -d "${TARGET}/${d}" ] && mv "${TARGET}/${d}" "${MEDIA_BAK}/"
    done
    rm -rf "${TARGET}"
    git clone --filter=blob:none --no-checkout "${CONFIG_REPO_URL}" "${TARGET}"
    cd "${TARGET}"
    for d in "${MEDIA_BAK}"/*; do
        [ -d "${d}" ] && mv "${d}" .
    done
    rmdir "${MEDIA_BAK}" 2>/dev/null || true
fi

cd "${TARGET}"
git fetch origin
git sparse-checkout init --cone
git sparse-checkout set "${SERVER}/" title_screens/
git reset --hard origin/main
# Scoped clean: drop untracked files inside repo-managed dirs so that files
# deleted upstream actually disappear from the live config. Never use
# `git clean -fdx` (would wipe operator-managed media in jukebox_music/,
# title_music/, reboot_themes/) or unscoped `git clean -fd` (would catch
# top-level operator-uploaded items). Limit to dirs that are 100%
# repo-managed.
git clean -fd "${SERVER}/" title_screens/

# Per-server overrides → top level
for f in motd.txt config.txt hippiestation_config.txt dynamic.json policy.json \
         jobs.txt maps.txt antag_rep.txt external_rsc_urls.txt; do
    [ -e "${SERVER}/${f}" ] && ln -sf "${SERVER}/${f}" "${f}"
done

# Secrets → top level (from host secrets dir)
for s in comms dbconfig webhooks tts_secrets; do
    [ -r "${SECRETS}/${s}" ] && ln -sf "${SECRETS}/${s}" "${s}.txt"
done

echo "[update-config] done: server=${SERVER} sha=$(git rev-parse --short HEAD)"
