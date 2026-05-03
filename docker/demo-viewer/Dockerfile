# ── Stage 1: Build the demo viewer ───────────────────────────────────────────
FROM node:18-alpine AS builder

RUN apk add --no-cache git

WORKDIR /build

# Clone our fork at build time so the image always ships the latest commits.
RUN git clone --depth=1 https://github.com/Nova-HippieStation/demo-viewer.git .

# Point the CNAME at our domain.
RUN echo "demo.owo.fm" > CNAME

# The text parser hardcodes the upstream Yogstation repo when fetching CSS/icons
# from jsDelivr.  Repoint it to our game repository so icons load correctly.
RUN sed -i 's|repo: "yogstation13/Yogstation"|repo: "Nova-HippieStation/NovaHippieStation"|g' \
        src/parser/text_parser.ts

RUN npm ci && npm run build

# ── Stage 2: Populate the shared volume on first start ───────────────────────
FROM alpine:3.19

COPY --from=builder /build/dist /demo-viewer-dist

# On `docker-compose up` this one-shot container copies the built files into
# the shared volume that Caddy serves and then exits immediately.
CMD ["/bin/sh", "-c", "cp -r /demo-viewer-dist/. /dist/ && echo 'Demo viewer files deployed to /dist'"]
