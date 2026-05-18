#!/usr/bin/env bash
# Sets $SERVER based on TGS instance name. Sourced by update-config.sh.
export SERVER="$(basename "$TGS_INSTANCE_ROOT")"
case "$SERVER" in
    ReduxStation) export SERVER=reduxstation ;;
    *) export SERVER="${SERVER:-reduxstation}" ;;
esac
