##############################################################################
# Webmap interactive site builder
#
# The page source (index.html, main.js, style.css) lives in a separate repo
# at https://github.com/ResurgenceStation/webmap so the viewer can ship updates
# without rebuilding the game image.  This Dockerfile clones that repo, drops
# in a pinned copy of Leaflet, and copies the result into a shared volume
# that Caddy serves at webmap.owo.fm.
#
# Bumping versions:
#     LEAFLET_VERSION=1.9.4   <- change this and rebuild
##############################################################################

# ── Stage 1: clone the page source + fetch Leaflet ───────────────────────────
FROM alpine:3.19 AS deps

ARG LEAFLET_VERSION=1.9.4
ARG WEBMAP_REPO=https://github.com/ResurgenceStation/webmap.git
ARG WEBMAP_REF=main

RUN apk add --no-cache git wget ca-certificates

# Clone the page source. --depth=1 keeps the image small.
RUN git clone --depth=1 --branch "${WEBMAP_REF}" "${WEBMAP_REPO}" /webmap-site

# Fetch a pinned copy of Leaflet so the running site has zero third-party
# network dependencies after deploy.
RUN mkdir -p /webmap-site/vendor/leaflet && \
    wget -q -O /webmap-site/vendor/leaflet/leaflet.js  \
        "https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.js"  && \
    wget -q -O /webmap-site/vendor/leaflet/leaflet.css \
        "https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.css" && \
    test -s /webmap-site/vendor/leaflet/leaflet.js && \
    test -s /webmap-site/vendor/leaflet/leaflet.css

# Drop the .git directory; the deployed site doesn't need it.
RUN rm -rf /webmap-site/.git

# ── Stage 2: assemble the dist tree ──────────────────────────────────────────
FROM alpine:3.19

COPY --from=deps /webmap-site /webmap-site

# On `docker-compose up` this one-shot container copies the bundled site
# into the shared volume that Caddy serves and then exits.
CMD ["/bin/sh", "-c", "cp -r /webmap-site/. /dist/ && echo 'Webmap site deployed to /dist'"]
