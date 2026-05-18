##############################################################################
# ReduxStation MediaWiki image
#
# Extends the official mediawiki:1.42.1 (LTS) image with:
#   * lua5.1 — required by Scribunto for {{#invoke:}} Lua modules used by
#     tgstation13 templates.
#   * The bundled extensions tgstation13's wiki uses (Scribunto, Cite,
#     ParserFunctions, SyntaxHighlight, TemplateData, CategoryTree) are
#     already shipped in /var/www/html/extensions in the upstream image;
#     we just enable them in LocalSettings.php at runtime.
#   * A thin entrypoint that waits for MariaDB and runs install.php on
#     first start, then hands off to apache2-foreground.
#
# LocalSettings.php is bind-mounted from docker/mediawiki/LocalSettings.php
# rather than baked into the image, so config changes don't require an
# image rebuild.
##############################################################################

FROM mediawiki:1.42.1

# Scribunto's standalone lua5.1 mode is the safest cross-platform choice
# (the alternative is luasandbox which needs a PECL extension and
# php-dev tooling we'd otherwise have to drag in).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lua5.1 \
        netcat-openbsd \
        git \
    && rm -rf /var/lib/apt/lists/*

# Extensions not bundled with mediawiki:1.42.1 that tg's wiki content depends
# on. Each is git-cloned at the REL1_42 branch so it stays in lockstep with
# the MW release.
#
#   Tabs — provides <tabs><tab name="..."> syntax used by Box Station etc.
ARG MW_BRANCH=REL1_42
RUN git clone --depth=1 --branch ${MW_BRANCH} \
        https://gerrit.wikimedia.org/r/mediawiki/extensions/Tabs \
        /var/www/html/extensions/Tabs

COPY entrypoint.sh /usr/local/bin/redux-mw-entrypoint
RUN chmod +x /usr/local/bin/redux-mw-entrypoint

ENTRYPOINT ["redux-mw-entrypoint"]
CMD ["apache2-foreground"]
