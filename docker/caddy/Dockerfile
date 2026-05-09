# Tiny extension of the upstream caddy image that creates the
# /etc/caddy/sites.d/ directory used by the main Caddyfile's
# `import /etc/caddy/sites.d/*.caddy` line. The directory is empty by
# default; operators can mount their own *.caddy snippets in via
# docker-compose.override.yml. With the directory always present, the
# import glob is a safe no-op when nothing's mounted.
FROM caddy:2-alpine

RUN mkdir -p /etc/caddy/sites.d
