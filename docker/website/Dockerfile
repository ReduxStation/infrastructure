##############################################################################
# Landing site builder (reduxstation.com / www.reduxstation.com)
#
# The page source lives in a separate repo at
# https://github.com/ReduxStation/website (Eleventy 3 + Webpack 5). This
# Dockerfile clones the repo at build time, runs the production build, and
# copies the resulting _site/ into a shared volume that Caddy serves.
#
# Pattern mirrors docker/webmap-site/Dockerfile and docker/demo-viewer/Dockerfile.
#
# Bumping versions:
#   WEBSITE_REF=master   <- pin to a tag if you want reproducible builds
##############################################################################

# ── Stage 1: clone the source and build ─────────────────────────────────────
FROM node:20-alpine AS build

ARG WEBSITE_REPO=https://github.com/ReduxStation/website.git
ARG WEBSITE_REF=master

RUN apk add --no-cache git

RUN git clone --depth=1 --branch "${WEBSITE_REF}" "${WEBSITE_REPO}" /website

WORKDIR /website
RUN npm ci --no-audit --no-fund
RUN npm run build

# ── Stage 2: bundle the dist for the shared volume ──────────────────────────
FROM alpine:3.19

COPY --from=build /website/_site /website-dist

# On `docker-compose up` this one-shot container copies the built site into
# the shared volume that Caddy serves at reduxstation.com / www.reduxstation.com
# and then exits immediately.
CMD ["/bin/sh", "-c", "cp -r /website-dist/. /dist/ && echo 'Website deployed to /dist'"]
