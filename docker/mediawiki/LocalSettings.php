<?php
// ReduxStation MediaWiki — hardened LocalSettings.
//
// Secrets and per-deploy values come from env vars set by docker-compose,
// not from this file, so the file can be world-readable inside the
// container without leaking credentials.
//
// File-by-file motivation for every setting is in the comments below.
// Anything not commented is a stock MediaWiki default we just need
// present.

if ( !defined( 'MEDIAWIKI' ) ) {
    exit;
}

// ─── Site identity ────────────────────────────────────────────────────────
$wgSitename = getenv( 'MEDIAWIKI_SITENAME' ) ?: 'ReduxStation Wiki';
$wgServer   = getenv( 'MEDIAWIKI_SERVER' )   ?: 'https://wiki.reduxstation.com';
$wgMetaNamespace = 'Wiki';
$wgScriptPath = '';
$wgArticlePath = '/wiki/$1';
$wgUsePathInfo = true;
$wgLogo = '/resources/assets/change-your-logo.svg';
$wgFavicon = '/favicon.ico';

// ─── Database ─────────────────────────────────────────────────────────────
$wgDBtype     = 'mysql';
$wgDBserver   = getenv( 'MEDIAWIKI_DB_HOST' )     ?: 'mariadb';
$wgDBname     = getenv( 'MEDIAWIKI_DB_NAME' )     ?: 'mediawiki';
$wgDBuser     = getenv( 'MEDIAWIKI_DB_USER' )     ?: 'ss13';
$wgDBpassword = getenv( 'MEDIAWIKI_DB_PASSWORD' ) ?: '';
$wgDBprefix   = '';
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=utf8mb4';

// ─── Keys: read from secret env vars, never commit ────────────────────────
// MEDIAWIKI_SECRET_KEY signs session cookies and CSRF tokens. Rotation
// invalidates all logged-in sessions but is otherwise safe.
// MEDIAWIKI_UPGRADE_KEY guards the /mw-config installer. Random per-deploy.
$wgSecretKey  = getenv( 'MEDIAWIKI_SECRET_KEY' )  ?: '';
$wgUpgradeKey = getenv( 'MEDIAWIKI_UPGRADE_KEY' ) ?: '';
if ( $wgSecretKey === '' ) {
    // Fail closed: a missing $wgSecretKey would silently let MW generate a
    // weak per-request key. Better to refuse to boot.
    throw new RuntimeException( 'MEDIAWIKI_SECRET_KEY env var must be set' );
}

// ─── Security headers / behaviour ─────────────────────────────────────────
$wgShowExceptionDetails = false;
$wgShowDBErrorBacktrace = false;
$wgShowSQLErrors        = false;
$wgDevelopmentWarnings  = false;

// Force HTTPS. The Caddy in front of MW is the TLS terminator; tell MW the
// scheme via X-Forwarded-Proto so wgServer-derived URLs come out https://.
$wgUsePrivateIPs = false;
$wgInternalServer = $wgServer;
if ( !empty( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) ) {
    $_SERVER['HTTPS'] = strtolower( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) === 'https' ? 'on' : 'off';
}
$wgCookieSecure = true;
$wgCookieHttpOnly = true;
$wgCookieSameSite = 'Lax';
$wgSessionName = $wgDBname . '_session';

// Bundled skins. The mediawiki:1.42.1 image ships these four under
// /skins/; since MW 1.24 they are no longer auto-loaded, so we have
// to register each one explicitly. wfLoadSkin('Vector') registers
// BOTH the legacy 'vector' and the modern 'vector-2022' (they ship
// as one bundle); $wgDefaultSkin picks which one new visitors see.
wfLoadSkin( 'Vector' );
wfLoadSkin( 'MonoBook' );
wfLoadSkin( 'Timeless' );
wfLoadSkin( 'MinervaNeue' );
$wgDefaultSkin = 'vector-2022';
$wgLanguageCode = 'en';

// ─── Permissions: locked down by default ──────────────────────────────────
// Anonymous users can READ but cannot edit, create pages, or create accounts.
// Account creation is admin-only. Edits restricted to logged-in users (the
// 'user' group), which only admins can create.
$wgGroupPermissions['*']['createaccount'] = false;
$wgGroupPermissions['*']['edit']          = false;
$wgGroupPermissions['*']['createpage']    = false;
$wgGroupPermissions['*']['createtalk']    = false;
$wgGroupPermissions['user']['edit']       = true;
$wgGroupPermissions['user']['createpage'] = true;
$wgGroupPermissions['user']['createtalk'] = true;

// Sysops keep the standard kit (block, delete, protect, import, etc.).
// import permission lets the admin run Special:Import — we'll rely on
// importDump.php from the CLI for the bulk import so leave this default.
$wgEmergencyContact = 'admin@reduxstation.com';
$wgPasswordSender   = $wgEmergencyContact;

// Password policy: require >= 10 chars for sysops, >= 8 for everyone else.
$wgPasswordPolicy['policies']['default']['MinimalPasswordLength'] = 8;
$wgPasswordPolicy['policies']['sysop']['MinimalPasswordLength']   = 10;

// Disable email delivery until SMTP is wired. MW still lets users set an
// email address; password resets are unavailable until $wgSMTP is set.
$wgEnableEmail = false;
$wgEnableUserEmail = false;

// ─── Uploads ──────────────────────────────────────────────────────────────
// Images are imported from the scrape, but new on-wiki uploads stay off
// until an operator opts in. Flip $wgEnableUploads to true and grant
// 'upload' permission to a trusted group when ready.
$wgEnableUploads = false;
$wgUploadDirectory = '/var/www/html/images';
$wgUploadPath = '/images';
$wgAllowImageMoving = true;
$wgFileExtensions = [ 'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'ogg' ];
$wgStrictFileExtensions = true;
$wgVerifyMimeType = true;

// ─── Caching ──────────────────────────────────────────────────────────────
$wgMainCacheType    = CACHE_ACCEL;
$wgMemCachedServers = [];
$wgEnableSidebarCache = true;

// ─── Extensions: minimum set to import from tgstation13 wiki ──────────────
// All of these ship with the mediawiki:1.42.1 image under /extensions/.
wfLoadExtension( 'ParserFunctions' );    // {{#if:}}, {{#switch:}}, {{#ifeq:}}
$wgPFEnableStringFunctions = true;
wfLoadExtension( 'Cite' );               // <ref></ref>, <references />
wfLoadExtension( 'SyntaxHighlight_GeSHi' );
wfLoadExtension( 'CategoryTree' );
wfLoadExtension( 'WikiEditor' );
wfLoadExtension( 'TemplateData' );
wfLoadExtension( 'Scribunto' );          // {{#invoke:Lua}} modules
$wgScribuntoDefaultEngine = 'luastandalone';
$wgScribuntoEngineConf['luastandalone']['luaPath'] = '/usr/bin/lua5.1';

// Disable the visual editor by default — it needs Parsoid as an external
// service and the scraped wiki is wikitext-native anyway. Re-enable once
// Parsoid is set up if you want WYSIWYG.

// Cite, ParserFunctions, and Scribunto are the ones tgstation13 templates
// hard-rely on. Without these the imported pages render as raw {{Template}}
// invocations.

// ─── Logging ──────────────────────────────────────────────────────────────
// Quiet by default. Bump to 'debug' temporarily when chasing problems.
$wgDebugLogFile = '';
$wgDebugToolbar = false;
$wgDebugComments = false;
$wgDebugDumpSql = false;

// Per-channel logging through MW's monolog support keeps verbose channels
// containable.
$wgDebugLogGroups = [
    'exception' => '/dev/stderr',
    'security'  => '/dev/stderr',
];

// ─── Performance ──────────────────────────────────────────────────────────
// Job queue runs synchronously by default — that's fine for our traffic.
$wgJobRunRate = 1;

// Allow large imports — the scraped XML can be tens of MB.
$wgMaxArticleSize = 8192;     // KB; default 2048
ini_set( 'memory_limit', '512M' );
ini_set( 'post_max_size', '128M' );
ini_set( 'upload_max_filesize', '128M' );
