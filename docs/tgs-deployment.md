# TGS Deployment Runbook

This codebase runs in production under [tgstation-server](https://github.com/tgstation/tgstation-server) (TGS) v6 or later. Bare DreamDaemon is not supported.

The deployment story is built on three TGS-6 native mechanisms:

1. `Configuration/GameStaticFiles/` for persistent data (TGS hard-links it into `Game/Live/` on every deploy).
2. `Configuration/EventScripts/` for the round-lifecycle hooks (`RoundStart.sh`, `RoundEnd.sh`).
3. A `LD_LIBRARY_PATH` env on the tgs container so BYOND's `call_ext()` resolves `rust_g.so` / `libBSQL.so` / `libquickwrite.so` directly out of `Game/Live/`.

No scatter scripts, no symlink shimming, no PostCompile or DreamDaemonPreLaunch. Everything that lives in `Game/Live/` after a deploy got there by TGS's own copy of the source tree (so changes auto-apply on the next compile).

## First-time install

After provisioning a host with Docker Engine + Compose v2, work through the steps below ONCE per instance.

### 1. Clone the repo and provision the env file

```bash
git clone https://github.com/ResurgenceStation/ResurgenceStation.git
cd ResurgenceStation
cp .env.example .env
$EDITOR .env  # set MYSQL_ROOT_PASSWORD and MYSQL_PASSWORD to strong values
```

### 2. Configure server-local overrides (optional)

Anything specific to one deployment lives in `docker-compose.override.yml`, which Compose merges automatically. Keeps the canonical compose file generic.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
mkdir -p caddy-sites.d
$EDITOR docker-compose.override.yml
```

The default override template enables the bundled TGS web control panel (the upstream image only ships the API by default) and mounts a `./caddy-sites.d/` directory at `/etc/caddy/sites.d/` inside the Caddy container. The canonical `docker/caddy/Caddyfile` ends with `import /etc/caddy/sites.d/*.caddy`, so anything you drop in `caddy-sites.d/<name>.caddy` becomes an additional site block on next reload, without touching the tracked Caddyfile.

If you want to reverse-proxy to a totally separate compose stack on the same host (e.g. a personal project hosted off the same domain), don't add it as a service block here. Run that project from its own directory with its own `docker-compose.yml`, give its container a network alias on this stack's default network, and add a snippet in `caddy-sites.d/<site>.caddy` that reverse-proxies to the alias.

### 3. Bring up the stack

```bash
docker compose build
docker compose up -d
```

The mariadb image's `/docker-entrypoint-initdb.d/01-init.sh` runs once on first volume creation and seeds:

- `ss13` schema (game database, with `tgstation_schema_prefixed.sql` + `mentor.sql` + `donator.sql` + `brdetector.sql`)
- `statbus` schema (slimbus alt_db)
- `tgs` schema (TGS server's own state, empty; TGS populates on first launch)

Grants the `ss13` user access to all three.

### 4. Pin BYOND to 516.1680 in the panel

Open the panel hostname (default `panel.owo.fm`; the canonical Caddyfile reverse-proxies it to `tgs:5000`) and complete TGS first-run setup: create initial admin, create instance, set repo URL.

In the **Engine** tab, install and activate **BYOND 516.1680**. `dependencies.sh` declares this exact build. Newer 516.x builds (1681+) have a regressed lexer that rejects integer-suffix CSS time units like `1500ms` inside DM multi-line strings, breaking `interface/stylesheet.dm` compilation.

### 5. Install the EventScript wrappers (once)

TGS-6 reads event scripts from `Configuration/EventScripts/`. Those files persist across deploys and TGS does NOT auto-update them from the repo on each compile (that is a deliberate design choice: the operator owns those scripts).

We still want every change to the round-lifecycle logic to auto-deploy from the repo. The way to get both is the **wrapper pattern**: install a thin wrapper at `Configuration/EventScripts/<EventName>.sh` once. The wrapper detects its own filename via `$0` and forwards execution to `$GAME_DIR/tools/tgs_scripts/<EventName>.sh`, the real script which is deployed fresh from the repo on every TGS compile.

To install:

1. In TGS panel -> Files & Scripts, for each event name below:
   - **CREATE** `<EventName>.sh` (or **REPLACE** if one already exists).
   - **PASTE** the contents of `tools/tgs_scripts/installers/EventScript-wrapper.sh` from this repo.
   - Save.

   Events to install wrappers for:
   - `RoundStart.sh`
   - `RoundEnd.sh`

2. **DELETE** any leftover scripts from the old custom pipeline if they exist:
   - `PostCompile.sh`
   - `DreamDaemonPreLaunch.sh`
   - `PreCompile.sh`

That is the only manual setup. After this, every deploy auto-updates the real script logic with no operator action.

#### What the event scripts do

| Script | TGS-6 event | Purpose |
|---|---|---|
| `RoundStart.sh` | `RoundStart` (custom, fired by DMAPI `TgsTriggerEvent("RoundStart", list("[round_id]"))` in `code/controllers/subsystem/dbcore.dm`) | Writes the new round id to `$GAME_DIR/data/serverinfo.json`. That path resolves through the TGS GameStaticFiles hard-link back to the persistent volume, where the public-log-parser polls it. The parser 404s the round's log directory until `RoundEnd` clears the file. |
| `RoundEnd.sh` | `RoundEnd` (custom, fired by DMAPI `TgsTriggerEvent("RoundEnd", list("[round_id]"))`) | Clears the active-round list in `$GAME_DIR/data/serverinfo.json` so the log-parser stops hiding the round. |

For the canonical list of TGS-6 events, when they fire, and what arguments each receives, see [`EventType.cs`](https://github.com/tgstation/tgstation-server/blob/master/src/Tgstation.Server.Host/Components/Events/EventType.cs) upstream. Filename rules: `.sh` extension required on Linux, case-sensitive prefix match against the event name, multiple files with the same prefix all fire in deterministic order.

### 6. Wire the auto-deploy GitHub Actions workflow (optional but recommended)

If you want every merge to master to auto-deploy, configure four repository secrets under `Settings -> Secrets and variables -> Actions`:

| Secret | Value |
|---|---|
| `TGS_URL` | Your TGS panel URL (e.g. `https://panel.owo.fm`) |
| `TGS_USERNAME` | Name of a TGS user with the perms below |
| `TGS_PASSWORD` | Password for that user |
| `TGS_INSTANCE_ID` | Numeric instance id (visible as `(N)` after the instance name in the panel header) |

Create that TGS user with the minimum perm set:

- **Repository -> Update Branch** (so the workflow can `POST /api/Repository {"updateFromOrigin": true}`)
- **Deployment -> Create Deployment** (so the workflow can `PUT /api/DreamMaker`)

Granting more is harmless but unnecessary; granting less makes the workflow 403 on either step. The whoami probe in `.github/workflows/tgs-auto-deploy.yml` will dump the user's effective perms in the run log if anything misroutes.

If the secrets are unset, the workflow logs a notice and exits 0. It does not redden master CI.

## How the native libraries reach BYOND

`rust_g.so`, `libBSQL.so`, and `libquickwrite.so` are committed to the repo root. Every TGS deploy copies them to `Game/Live/<name>` via the normal source-tree copy (`tools/deploy.sh`).

BYOND's `call_ext("rust_g", ...)` on Linux maps to `dlopen("rust_g.so")`: the literal call_ext name plus `.so`, no `lib-` prefix. Verified empirically by inspecting the live DreamDaemon's `/proc/<PID>/maps`, which shows the lib loaded from `.../rust_g.so` (not `rust_g` and not `librust_g.so`). `dlopen` does NOT search the current working directory; it searches `LD_LIBRARY_PATH` and the ldconfig cache.

TGS-6 launches DreamDaemon via a wrapper script that does:

```sh
export LD_LIBRARY_PATH="$ORIGIN:$LD_LIBRARY_PATH"
```

where `$ORIGIN` is the BYOND `bin/` dir. The `$LD_LIBRARY_PATH` on the right-hand side is whatever the TGS process inherits. We set it on the tgs service in `docker-compose.yml`:

```yaml
environment:
  LD_LIBRARY_PATH: /tgs_instances/ResurgenceStation/Game/Live
```

So DreamDaemon's effective search path is `BYOND/bin/:Game/Live/`. BYOND finds the literal `rust_g.so` file (along with `libBSQL.so` and `libquickwrite.so`) in `Game/Live/` via this path. No scatter script required. Every deploy refreshes the lib contents automatically because TGS copies the repo source tree (including the committed libs) into `Game/Live/` on every compile.

The `build-native-libs.yml` workflow rebuilds `rust_g.so` from the `rust_g_builder` stage of `Dockerfile` and auto-commits any drift, so a Dockerfile change to rust_g's build flags propagates without anyone running `docker compose build` by hand.

## How persistent data survives across deploys

TGS-6 has a native mechanism for files that persist across deploys: `Configuration/GameStaticFiles/`. Anything placed under that directory is hard-linked into the deployed game directory on every deploy.

For this stack, the persistent `game_data` Docker volume is mounted **directly at the TGS GameStaticFiles path** inside the tgs container, in `docker-compose.yml`:

```yaml
- game_data:/tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data
```

This matches the upstream tgstation `RUNNING_A_SERVER.md` recipe ("data should be initially created as an empty directory. The game stores persistent data here"). TGS sees `Configuration/GameStaticFiles/data/`, hard-links its contents into `Game/Live/data/` on every deploy. The game writes to `data/foo` relative to its CWD (which is `Game/Live/`), and the write resolves through the hard-link back to the persistent volume.

The same volume is mounted read-only into the statbus container at `/srv/gamestatic`, the Caddy container at `/srv/logs`, and the log-parser container at `/logs` so all four services share one source of truth for round logs.

## Per-deploy workflow

In normal operation, every PR merged into `master` triggers the `TGS auto-deploy` workflow. It:

1. Logs into the TGS HTTP API at `${TGS_URL}/api/` with the `TGS_USERNAME` / `TGS_PASSWORD` repository secrets.
2. `POST /api/Repository {"updateFromOrigin": true}` pulls the new HEAD on the live instance.
3. Waits for the repo-update job to actually finish (fails the workflow loudly on a merge conflict from a stale testmerge).
4. `PUT /api/DreamMaker` queues a fresh compile.
5. Waits for the compile job to finish (the TGS exceptionDetails surface the exact compiler error if it dies).

TGS hot-swaps the watchdog on a successful compile. The running round is unaffected; the next round runs the new code.

PRs that have NOT been merged stay testable through TGS's **Test Merge** feature on the panel.

### Manual deploy fallback

If the auto-deploy workflow is broken or you want to deploy without merging (e.g. during incident response), the panel works end-to-end:

1. **Repository tab** -> Reset/Update from Remote (pulls the latest master).
2. **Deployment tab** -> Deploy. TGS clones, runs DreamMaker, then hot-swaps the game.
3. Watch the **Jobs** tab for the compile and watchdog launch.

You can also fire the workflow on demand from the GitHub UI (Actions -> TGS auto-deploy -> Run workflow) without merging anything, since it has `workflow_dispatch:` enabled.

## Migrating an existing deployment

If you are pointing a fresh checkout at an existing `mariadb_data` volume (rather than starting fresh), `01-init.sh` will not run. It only fires on first volume creation. Manually create the `tgs` database that the seed would have made:

```bash
docker exec -e MPW="$MYSQL_ROOT_PASSWORD" <mariadb_container> \
  mariadb -uroot -p"$MPW" -e \
  "CREATE DATABASE IF NOT EXISTS tgs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   GRANT ALL PRIVILEGES ON tgs.* TO 'ss13'@'%';
   FLUSH PRIVILEGES;"
```

For nuking and rebuilding game data without touching TGS state (panel users, deploy history, instance config), use `tools/wipe-game-data.sh --yes-i-mean-it`. It drops and re-seeds `ss13` and `statbus` from the schema files baked into the mariadb image and clears `data/logs/*` plus `serverinfo.json` on the persistent volume. The `tgs` schema is intentionally untouched.

### Migrating from the old PostCompile/DreamDaemonPreLaunch pipeline

If you are upgrading from a checkout that still had the old `PostCompile.sh` / `DreamDaemonPreLaunch.sh` scripts:

1. In TGS panel -> Files & Scripts, DELETE the old scripts (`PostCompile.sh`, `DreamDaemonPreLaunch.sh`, and any `PreCompile.sh`).
2. Install the wrappers per step 5 of the first-time install above.
3. Remove any stale `rust_g` copies from `Byond/<active_version>/byond/bin/` left over from the old scatter (otherwise BYOND finds the stale `BYOND/bin/` copy first and never reaches the fresh `Game/Live/` copy):
   ```bash
   docker exec <tgs_container> sh -c \
     'ACTIVE=$(cat /tgs_instances/ResurgenceStation/Byond/ActiveVersion.txt); \
      rm -f /tgs_instances/ResurgenceStation/Byond/$ACTIVE/byond/bin/rust_g \
            /tgs_instances/ResurgenceStation/Byond/$ACTIVE/byond/bin/rust_g.so \
            /tgs_instances/ResurgenceStation/Byond/$ACTIVE/byond/bin/librust_g.so \
            /tgs_instances/ResurgenceStation/Byond/$ACTIVE/byond/bin/libBSQL.so \
            /tgs_instances/ResurgenceStation/Byond/$ACTIVE/byond/bin/libquickwrite.so'
   ```
4. `docker compose up -d --force-recreate tgs` to pick up the `LD_LIBRARY_PATH` env and the new mount at `Configuration/GameStaticFiles/data`.
5. Trigger one fresh deploy from the panel. From this point on, every change to `tools/tgs_scripts/*.sh` or any committed lib propagates with the next compile.

## Common failures

### "libbyond.so: undefined symbol: log_write" (or similar) at world.New()

```
Runtime in code/__HELPERS/_logging.dm, line 174:
/tgs_instances/.../Byond/<ver>/byond/bin/libbyond.so: undefined symbol: log_write
proc name: log world (/proc/log_world)
src: null
call stack:
log world("World loaded at HH:MM:SS!")
world: New()
```

BYOND's dlopen chain failed to find `rust_g.so`. The misleading error message blames `libbyond.so`, but the real problem is `LD_LIBRARY_PATH` not resolving to a directory that contains the lib.

Diagnose:

```bash
# 1. Is the lib in Game/Live where TGS deployed it?
docker exec <tgs_container> ls -la /tgs_instances/ResurgenceStation/Game/Live/rust_g.so

# 2. Is LD_LIBRARY_PATH set on the tgs container env?
docker exec <tgs_container> env | grep LD_LIBRARY_PATH
# Should print: LD_LIBRARY_PATH=/tgs_instances/ResurgenceStation/Game/Live

# 3. What is DreamDaemon's effective search path? /proc/<DD_PID>/maps tells you
# which rust_g.so the running game actually loaded.
docker exec <tgs_container> sh -c 'pgrep -af DreamDaemon'
docker exec <tgs_container> cat /proc/<DD_PID>/maps | grep -i rust_g
```

Fix:

- If `Game/Live/rust_g.so` is missing: re-deploy. `tools/deploy.sh` should copy it from the repo root.
- If `LD_LIBRARY_PATH` is unset on the container: confirm `docker-compose.yml` has the `environment.LD_LIBRARY_PATH` line on the `tgs` service, then `docker compose up -d --force-recreate tgs`.
- If `/proc/<DD_PID>/maps` shows the lib loaded from `Byond/<ver>/byond/bin/`, there is a stale copy from the old scatter shadowing the fresh one. Remove the stale files (see the migration recipe above) and restart the watchdog from the panel.

### "BSQL library failed to provide connect operation for connection id (MySql)"

Same root cause as `log_write`: BYOND's dlopen chain did not find `libBSQL.so`. Same diagnosis (check `Game/Live/libBSQL.so` exists, `LD_LIBRARY_PATH` is set, no stale copy in `Byond/bin/`).

### Logs at logs.owo.fm 404 even though the game is writing round files

The active game directory's `data/` is not resolving back to the persistent volume. Three things to check:

1. Confirm the `game_data` volume is mounted at the right TGS path:
   ```bash
   docker inspect <tgs_container> | jq '.[0].Mounts[] | select(.Destination | contains("GameStaticFiles"))'
   ```
   Destination should be `/tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data`.
2. Confirm TGS hard-linked it on the latest deploy:
   ```bash
   docker exec <tgs_container> stat -c '%i' \
     /tgs_instances/ResurgenceStation/Game/Live/data/ \
     /tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data/
   ```
   The two inodes should match (or both contain the same files at matching inodes for nested entries).
3. If the parser sees a stale `serverinfo.json`, the `RoundStart.sh` wrapper did not fire or the real script under `tools/tgs_scripts/RoundStart.sh` could not write. Tail the TGS instance log for the event:
   ```bash
   docker exec <tgs_container> tail -n 200 /tgs_logs/<instance>/*.log | grep -i RoundStart
   ```

### "DMAPI interop version is less than tgstation-server's version"

The codebase's bundled DMAPI is older than the running TGS server. The library lives in `code/modules/tgs/` and `code/__DEFINES/tgs.dm`. The `.github/workflows/dmapi-updater.yml` workflow opens a PR with the bump on a weekly schedule; merge it (after fixing any consumer-side compile errors that surface, typical drift: chat command `Run` signature changes, test_merge field renames).

### "instance cannot be placed at the given path because it is not empty"

A bind mount in `docker-compose.yml` is pre-creating the instance directory tree before TGS gets a chance to populate it. Confirm `docker-compose.yml` does NOT bind-mount any path under `/tgs_instances/<instance>/` other than the `game_data` volume at `Configuration/GameStaticFiles/data` (which is fine because TGS expects that path to exist and be populated by the operator).

If you see this error AFTER a deploy that worked previously, an older copy of the compose file probably had a `./config:/tgs_instances/.../Configuration/GameStaticFiles/config` bind mount that has since been removed; drop it from your compose file, restart TGS, recreate the instance via the panel, then copy your live game config into the volume's `Configuration/GameStaticFiles/config/` directory.

### Webpanel only shows a logo

`ControlPanel.Enable` defaults to `false` in the bundled TGS configuration. The `docker-compose.override.yml.example` template includes the override block that flips it on:

```yaml
services:
  tgs:
    environment:
      ControlPanel__Enable: "true"
      ControlPanel__AllowAnyOrigin: "true"
```

If your override file is missing this, copy the block in and `docker compose up -d tgs`.
