##############################################################################
# Webmap tile renderer
#
# This image contains dmm-tools (compiled from SpacemanDMM) and Python/Pillow.
# The game source is NOT baked in — it is bind-mounted at /src at runtime so
# the image stays small and doesn't need rebuilding after map edits.
#
# How it works in docker-compose:
#   1. docker-compose build webmap-renderer     (compiles dmm-tools — ~10 min once)
#   2. docker-compose up webmap-renderer        (renders tiles → /tiles volume)
#   3. Caddy serves the tiles at tiles.owo.fm (consumed by webmap.owo.fm)
#
# Force a re-render after a map change:
#   docker-compose run --rm webmap-renderer     (volume already exists → skips)
#   docker volume rm <project>_webmap_tiles && docker-compose up webmap-renderer
##############################################################################

# ── Stage 1: compile dmm-tools from source ───────────────────────────────────
FROM rust:1-slim-bookworm AS dmm-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# SpacemanDMM: dmm-tools minimap renders a DMM map file to per-z-level PNGs.
# Building from source guarantees the binary matches the host OS/libc.
RUN git clone --depth=1 https://github.com/SpaceManiac/SpacemanDMM.git /spacedmm
WORKDIR /spacedmm
# --bin dmm-tools targets the binary by name across the whole workspace;
# -p dmm-tools would only build the package (which may be library-only).
# strip is best-effort: it reduces binary size but isn't required.
RUN cargo build --release --bin dmm-tools \
    && (strip target/release/dmm-tools 2>/dev/null || true) \
    && echo "Built: $(ls -lh target/release/dmm-tools)"

# ── Stage 2: runtime renderer image ──────────────────────────────────────────
FROM python:3.12-slim-bookworm

RUN pip install --no-cache-dir Pillow

COPY --from=dmm-builder /spacedmm/target/release/dmm-tools /usr/local/bin/dmm-tools

# tile.py: slices each flat PNG into a Leaflet XYZ tile pyramid
COPY docker/webmap/tile.py /tile.py

# extract_objects.py: builds objects.json (BYOND-coord-keyed metadata) for
# the interactive viewer at webmap.owo.fm
COPY docker/webmap/extract_objects.py /extract_objects.py

# render.sh: orchestrates dmm-tools → tile.py + extract_objects.py
COPY docker/webmap/render.sh /render.sh
RUN chmod +x /render.sh

# Game source is mounted read-only at /src by docker-compose.
# Tiles are written to /tiles (a named volume shared with Caddy).
VOLUME ["/src", "/tiles"]

CMD ["/render.sh"]
