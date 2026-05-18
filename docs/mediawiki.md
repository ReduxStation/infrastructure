# MediaWiki at wiki.reduxstation.com

A hardened MediaWiki 1.42.1 instance served by Caddy at
`https://wiki.reduxstation.com`. Sits on the existing MariaDB
container; uses one dedicated database (`mediawiki`) accessed by the
same `ss13` MariaDB user used by the rest of the stack.

## First-time setup

### 1. Operator secrets in `.env.local`

The mediawiki service refuses to start unless these are set:

```
MEDIAWIKI_ADMIN_USER=redux-admin           # initial sysop username; optional, defaults to redux-admin
MEDIAWIKI_ADMIN_PASSWORD=<choose-a-strong-one>
MEDIAWIKI_SECRET_KEY=<openssl rand -hex 32>
MEDIAWIKI_UPGRADE_KEY=<openssl rand -hex 16>
```

`MEDIAWIKI_ADMIN_PASSWORD` is consumed once on first install. Change it
in-app via `Special:ChangePassword` after first login; the env var
remains a fallback for the install marker.

### 2. DNS

Add an A record for `wiki.reduxstation.com` pointing at the host
(matches the other subdomains). Without it Caddy can't fetch a Let's
Encrypt cert and the site won't respond.

### 3. Pull, install volumes, start

```bash
cd /srv/redux/infrastructure
git pull
./deploy/install-host.sh                          # creates mediawiki_images volume
docker compose build mediawiki
docker compose up -d mediawiki
docker compose up -d --force-recreate caddy       # pick up wiki.reduxstation.com block
```

First start runs `maintenance/install.php` which:

1. Connects to MariaDB as `ss13` against the `mediawiki` database
2. Creates the schema (~70 tables)
3. Inserts the initial sysop row from `MEDIAWIKI_ADMIN_*`
4. Drops `images/.redux-installed` as the first-run marker
5. Hands off to apache2-foreground

Watch logs:

```bash
docker compose logs -f mediawiki
```

You should see `[redux-mw] handing off to apache` when it's done.
`curl -I https://wiki.reduxstation.com/` should return 200.

Sign in at `https://wiki.reduxstation.com/wiki/Special:UserLogin`
with `MEDIAWIKI_ADMIN_USER` / `MEDIAWIKI_ADMIN_PASSWORD`.

## Importing the wiki-scraper output

The scraper at `https://github.com/s950tx16wasr10/wiki-scraper`
produces a single MediaWiki XML file with one revision per page,
filtered to the closest-to-2021-01-01 policy.

```bash
# Copy the XML into the mediawiki container.
docker cp /path/to/redux-2021-01-01.xml reduxstation-mediawiki-1:/tmp/import.xml

# Run importDump.php. --quiet drops the per-page logging; remove it
# for verbose progress on big dumps.
docker compose exec mediawiki php /var/www/html/maintenance/importDump.php \
    --quiet --conf /var/www/html/LocalSettings.php < /tmp/import.xml

# Rebuild caches that importDump.php doesn't touch.
docker compose exec mediawiki php /var/www/html/maintenance/rebuildrecentchanges.php
docker compose exec mediawiki php /var/www/html/maintenance/initSiteStats.php --update
```

Expected wall-clock for a tgstation13-sized snapshot (~15k pages,
~30k revisions): 10–30 minutes depending on disk speed.

If the import hits a template or Lua module that errors at parse
time, the page still imports — the error renders inline when the
page is viewed. Re-running `importDump.php` is idempotent: pages
already at the imported revision are skipped.

## Locked-down by default

`docker/mediawiki/LocalSettings.php` ships with:

| Setting                                 | Value | Why                                                  |
|-----------------------------------------|-------|------------------------------------------------------|
| `$wgGroupPermissions['*']['edit']`      | false | Anonymous edits off                                  |
| `$wgGroupPermissions['*']['createaccount']` | false | Account creation only via sysop UserRights      |
| `$wgEnableUploads`                      | false | Upload via Special:Upload is off until you opt in    |
| `$wgEnableEmail`                        | false | Email features off until you configure SMTP          |
| `$wgShowExceptionDetails`               | false | Stack traces stay in container logs                  |
| `$wgCookieSecure`                       | true  | Cookies only over HTTPS                              |
| `$wgCookieHttpOnly`                     | true  | JS can't read session cookies                        |
| `$wgCookieSameSite`                     | Lax   | CSRF defence                                         |
| Password floor                          | 8/10  | 8 chars for users, 10 for sysops                     |

To flip uploads on once you want them:

```php
// edit docker/mediawiki/LocalSettings.php
$wgEnableUploads = true;
$wgGroupPermissions['user']['upload'] = false;  // sysops only
$wgGroupPermissions['sysop']['upload'] = true;
$wgGroupPermissions['sysop']['reupload'] = true;
```

Then `docker compose up -d --force-recreate mediawiki` to remount.

## Creating additional sysops

```bash
docker compose exec mediawiki php /var/www/html/maintenance/createAndPromote.php \
    --sysop --bureaucrat "Username" "TempPassword"
```

Then the user logs in and changes their password via `Special:ChangePassword`.

## Recovery: forgot the admin password

```bash
docker compose exec mediawiki php /var/www/html/maintenance/changePassword.php \
    --user="${MEDIAWIKI_ADMIN_USER}" --password='NewSecret'
```

## Backing up

The mediawiki state lives in two places:

1. **MariaDB `mediawiki` database** — backed up with the rest of
   MariaDB via whatever schedule is set on the `mariadb_data` volume.
   `mariadb-dump -uss13 -p mediawiki > mediawiki.sql` for an ad-hoc
   dump.
2. **`reduxstation_mediawiki_images` Docker volume** — only matters
   when uploads are enabled. Snapshot the volume directory at
   `/var/lib/docker/volumes/reduxstation_mediawiki_images/_data/`.
