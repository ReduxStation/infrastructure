#!/usr/bin/env bash
# Sets $SERVER based on TGS instance name. Sourced by update-config.sh.
export SERVER="$(basename "$TGS_INSTANCE_ROOT")"
case "$SERVER" in
    ResurgenceStation) export SERVER=owo ;;
    *) export SERVER="${SERVER:-owo}" ;;
esac
