Real secret values live on the host at /etc/resurgence/secrets/* (mode 0400 root:root).
This directory tracks only NAMES (in schema.txt), never values.

Phase 4 of the migration runs deploy/populate-secrets.sh which prompts for each
secret and writes the file. No values ever enter this repo.
