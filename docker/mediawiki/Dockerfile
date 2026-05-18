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
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/redux-mw-entrypoint
RUN chmod +x /usr/local/bin/redux-mw-entrypoint

ENTRYPOINT ["redux-mw-entrypoint"]
CMD ["apache2-foreground"]
