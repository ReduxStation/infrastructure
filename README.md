# ReduxStation infrastructure

Operator-managed deployment infrastructure: docker-compose, Dockerfiles,
TGS EventScripts source, deploy scripts, sysctl tuning.

## Layout
- `docker-compose.yml` — full stack, project name `reduxstation` pinned.
- `globals.env` — single source of truth for non-secret cross-cutting variables.
  Sourced by docker-compose (via .env symlink), every EventScript, every deploy script.
- `docker/` — per-service build dirs.
- `tgs/EventScripts/reduxstation/` — source-of-truth event scripts populated to
  `/etc/tgs-EventScripts.d/reduxstation/` by `deploy/install-eventscripts.sh`.
- `deploy/` — operator scripts (install-host, install-eventscripts, populate-secrets, etc.)
- `secrets/` — schema only. Real values at `/etc/redux/secrets/`.
- `slimbus/` — submodule, consumed by caddy + statbus.

## Operator workflow
See `docs/runbook.md`.
