# TGS Deployment Runbook

This codebase runs in production under [tgstation-server](https://github.com/tgstation/tgstation-server) (TGS) v6 or later. Bare DreamDaemon is no longer supported.

## First-time install

After standing up TGS and the supporting containers (mariadb, statbus, caddy, etc.), perform the steps below ONCE per instance. They are not idempotent across the codebase, only across the TGS instance volume.

### 1. Pin BYOND to 516.1680

`dependencies.sh` declares `BYOND_MAJOR=516, BYOND_MINOR=1680`. The TGS Engine tab must install and activate this exact build. Newer builds (e.g. 516.1681 and later) have a regressed lexer that rejects integer-suffix CSS time units like `1500ms` inside DM multi-line strings. Sticking to 1680 keeps `interface/stylesheet.dm` compiling.

### 2. Install the TGS event scripts

Four scripts in `tools/tgs4_scripts/` need to be copied into the TGS instance volume:

| Script | Installs as | Purpose |
|---|---|---|
| `PostCompile.sh` | `Configuration/EventScripts/PostCompile` | Scatters `librust_g.so`, `libBSQL.so`, `libquickwrite.so` into `/usr/local/lib` after each compile. Without this, DB connections fail with "BSQL library failed to provide connect operation". |
| `PreStartup.sh` | `Configuration/EventScripts/PreStartup` | Symlinks the active game's `data/logs` directory to the persistent `/tgstation/data/logs` mount. Without this, new round logs do not appear at `logs.owo.fm`. Also seeds `/tgstation/data/serverinfo.json` so the log-parser does not block all rounds on a brand new deploy. |
| `RoundStart.sh` | `Configuration/EventScripts/RoundStart` | Receives the new round's id from the game via `TgsTriggerEvent("RoundStart", ...)` and writes it into `/tgstation/data/serverinfo.json`. The public-log-parser polls this file and 404s the active round's directory until `RoundEnd` fires. |
| `RoundEnd.sh` | `Configuration/EventScripts/RoundEnd` | Receives the ended round's id and clears `/tgstation/data/serverinfo.json` so the log-parser stops hiding it. |

The compile pipeline drops the native libs into the freshly built game directory, but BYOND's i386 process searches `/usr/local/lib` and the `ldconfig` cache, NOT the game directory. PostCompile fixes that.

The game writes round logs relative to its working directory under `Game/<uuid>/data/logs/`. Caddy serves logs from the `game_data` volume mounted at `/tgstation/data/logs`. PreStartup bridges the two with a symlink.

Install all four at once. From a host with Docker access:

```bash
INSTANCE=ResurgenceStation
INSTANCE_VOL=resurgencestation_tgs_instances
REPO_DIR=~/ResurgenceStation
for SCRIPT in PostCompile PreStartup RoundStart RoundEnd; do
  docker run --rm \
    -v "$REPO_DIR/tools/tgs4_scripts":/src:ro \
    -v "$INSTANCE_VOL":/v \
    alpine sh -c "cp /src/$SCRIPT.sh /v/$INSTANCE/Configuration/EventScripts/$SCRIPT && chmod +x /v/$INSTANCE/Configuration/EventScripts/$SCRIPT"
done
```

You can also edit them later through the TGS panel **Files & Scripts** tab.

The `tools/tgs4_scripts/` folder name is legacy from TGS3/TGS4 conventions where event scripts lived in the codebase. TGS6+ reads scripts from the instance Configuration directory instead, but we keep the folder in the codebase as the reference source so anyone setting up a new instance has a known good script to copy.

### 3. Fix the slimbus remote (if cloning from an old deploy)

The `slimbus/` directory used to be a submodule pointing at the deprecated HippieStation/slimbus repo. If your `slimbus/` checkout still has that as origin, repoint it:

```bash
cd slimbus
git remote set-url origin https://github.com/ResurgenceStation/slimbus
git fetch origin
git checkout master
git reset --hard origin/master
```

Then rebuild the statbus container:

```bash
docker-compose build statbus
docker-compose up -d statbus
```

### 4. Wipe and seed the databases (only on a brand-new install)

The `docker/mysql-init/01-init.sh` script runs ONCE on first MariaDB volume creation. It loads `tgstation_schema_prefixed.sql`, `mentor.sql`, `donator.sql`, `brdetector.sql`, and `slimbus/sql/alt_db.sql`. If you are migrating an existing volume rather than starting fresh, the init script will not run and you must create the `tgs` database manually:

```bash
docker exec -e MPW="$MYSQL_ROOT_PASSWORD" <mariadb_container> \
  mariadb -uroot -p"$MPW" -e \
  "CREATE DATABASE IF NOT EXISTS tgs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   GRANT ALL PRIVILEGES ON tgs.* TO 'ss13'@'%';
   FLUSH PRIVILEGES;"
```

## Per-deploy workflow

Once the first-time setup is done, deploys are driven entirely from the TGS panel:

1. **Repository tab** → Reset/Update from Remote (pulls the latest master).
2. **Deployment tab** → Deploy. TGS clones, runs DreamMaker, runs PostCompile to scatter native libs, then hot-swaps the game.
3. Watch the **Jobs** tab for the compile and watchdog launch.

The `~/apply-customizations.sh` script on the live owo.fm server takes care of post-pull Caddyfile customizations (the `panel.owo.fm` rename and the pokelabs block) on each `git pull`. It is not part of TGS's flow and only matters if you are manually pulling on the host outside of TGS.

## Common failures

### Logs at logs.owo.fm 404 even though the game is writing round files

The PreStartup script did not run, or it failed before symlinking. Check that the game's working dir has `data/logs` as a symlink to the persistent path:

```bash
docker exec <tgs_container> ls -la /tgs_instances/<instance>/Game/Live/data/logs
```

Should show `-> /tgstation/data/logs`. If it shows a real directory instead, run the script manually:

```bash
docker exec <tgs_container> /tgs_instances/<instance>/Configuration/EventScripts/PreStartup /tgs_instances/<instance>/Game/Live
```

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

BYOND's `call_ext()` resolution checks the game working directory under several name variants (bare, `.so`, `lib-` prefix) and the BYOND install's own `bin/` directory before falling back to `LD_LIBRARY_PATH` and the `ldconfig` cache. When none of those satisfy, dlopen fails and BYOND reports the error as if `libbyond.so` itself has an undefined symbol. The misleading message blamed `libbyond.so` even though the real problem was that the rust_g binary was only at `/usr/local/lib/{rust_g,librust_g}.so` and missing from every other path BYOND checks first.

Fixed by extending PostCompile to scatter every native lib (`librust_g.so`, `libBSQL.so`, `libquickwrite.so`) to all four location families:

| Family | Variants written |
|---|---|
| Game working dir (`$1`) | `<BASE>`, `<BASE>.so`, `lib<BASE>.so` |
| `/usr/local/lib` | `<BASE>.so`, `lib<BASE>.so` |
| `/usr/lib/i386-linux-gnu` | `<BASE>.so`, `lib<BASE>.so` |
| BYOND `bin/` (read from `Byond/ActiveVersion.txt`) | `<BASE>`, `<BASE>.so`, `lib<BASE>.so` |

The current `tools/tgs4_scripts/PostCompile.sh` does this. If you see the runtime, install the latest PostCompile and run it manually for the active Game/Live, then restart the watchdog so DD re-dlopens fresh.

### "BSQL library failed to provide connect operation for connection id (MySql)"

Same root cause as the `log_write` runtime above (BYOND's `call_ext` dlopen chain not finding the lib in the path it checks first). Same fix: install the latest PostCompile, run it for Game/Live, restart the watchdog. To verify after install:

```bash
docker exec <tgs_container> ldconfig -p | grep -iE "BSQL|rust_g|quickwrite"
```

You should see all three. If not, ensure `Configuration/EventScripts/PostCompile` exists and is executable, then redeploy.

### "DMAPI interop version is less than tgstation-server's version"

The codebase's bundled DMAPI is older than the running TGS server. The library lives in `code/modules/tgs/` and `code/__DEFINES/tgs.dm`. Replace both from the upstream `tgstation/tgstation-server` master `src/DMAPI/` tree, fix any consumer-side compile errors that surface (typical drift: chat command Run signature changes, test_merge field renames), and PR the upgrade.

### "instance cannot be placed at the given path because it is not empty"

A bind mount in `docker-compose.yml` is pre-creating the instance directory tree before TGS gets a chance to populate it. Check that `docker-compose.yml` does NOT bind-mount any path under `/tgs_instances/<instance>/`. The `./config:` bind mount that older copies of the compose file used has been removed. If yours still has it, drop the line, restart TGS, and create the instance, then ensure your live game config is copied INTO the volume's `Configuration/GameStaticFiles/config/` directory (TGS-canonical location for static game files).

### Webpanel only shows a logo

`ControlPanel.Enable` defaults to `false` in the bundled TGS configuration. The live owo.fm deployment overrides this via `docker-compose.override.yml`:

```yaml
services:
  tgs:
    environment:
      ControlPanel__Enable: "true"
      ControlPanel__AllowAnyOrigin: "true"
```

If you run a fresh install, copy that block.
