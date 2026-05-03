#!/bin/sh
# render.sh — Render + tile the HippieStation map on container startup.
#
# Renders two persistent z-levels:
#   z=1  hippiestation.dmm   (station + space + CentComm)
#   z=2  Lavaland.dmm        (mining / lavaland)
#
# To force a full re-render, remove the webmap_tiles volume:
#   docker volume rm <project>_webmap_tiles
#   docker-compose up webmap-renderer

set -e

TILES_OUT=/tiles/hippiestation
MAPS_TMP=/tmp/maps
SRC=/src

# ── Skip if tiles already exist ───────────────────────────────────────────────
if [ -d "$TILES_OUT" ] && [ "$(ls -A "$TILES_OUT" 2>/dev/null)" ]; then
    echo "[webmap] Tiles already present in $TILES_OUT — skipping render."
    echo "[webmap] Remove the webmap_tiles volume to force regeneration."
    exit 0
fi

mkdir -p "$MAPS_TMP"

# dmm-tools resolves #include paths relative to $CWD; must cd to source root.
cd "$SRC"

# ── z=1: Main station ─────────────────────────────────────────────────────────
echo "[webmap] Rendering z=1 (station) …"
dmm-tools minimap \
    -o "$MAPS_TMP/" \
    tgstation.dme \
    _maps/map_files/HippieStation/hippiestation.dmm \
    2>&1 \
|| echo "[webmap] Warning: dmm-tools returned non-zero (parse warnings are normal)"

# dmm-tools names output hippiestation-1.png; normalise to our z=1 name.
for f in "$MAPS_TMP/"hippiestation-*.png; do
    [ -f "$f" ] || continue
    num=$(echo "$f" | grep -o '[0-9]*\.png$' | grep -o '[0-9]*')
    mv "$f" "$MAPS_TMP/z1_level${num}.png"
done

# ── z=2: Lavaland ─────────────────────────────────────────────────────────────
echo "[webmap] Rendering z=2 (lavaland) …"
dmm-tools minimap \
    -o "$MAPS_TMP/" \
    tgstation.dme \
    _maps/map_files/Mining/Lavaland.dmm \
    2>&1 \
|| echo "[webmap] Warning: dmm-tools returned non-zero (parse warnings are normal)"

# Rename Lavaland-N.png → z2_levelN.png
for f in "$MAPS_TMP/"Lavaland-*.png "$MAPS_TMP/"lavaland-*.png; do
    [ -f "$f" ] || continue
    num=$(echo "$f" | grep -o '[0-9]*\.png$' | grep -o '[0-9]*')
    mv "$f" "$MAPS_TMP/z2_level${num}.png"
done

# ── z=3: CentCom ──────────────────────────────────────────────────────────────
echo "[webmap] Rendering z=3 (centcom) …"
dmm-tools minimap \
    -o "$MAPS_TMP/" \
    tgstation.dme \
    _maps/map_files/generic/CentCom.dmm \
    2>&1 \
|| echo "[webmap] Warning: dmm-tools returned non-zero (parse warnings are normal)"

# Rename CentCom-N.png → z3_levelN.png
for f in "$MAPS_TMP/"CentCom-*.png "$MAPS_TMP/"centcom-*.png; do
    [ -f "$f" ] || continue
    num=$(echo "$f" | grep -o '[0-9]*\.png$' | grep -o '[0-9]*')
    mv "$f" "$MAPS_TMP/z3_level${num}.png"
done

echo "[webmap] All rendered PNGs:"
ls "$MAPS_TMP"/*.png 2>/dev/null || { echo "[webmap] ERROR: No PNGs produced!"; exit 1; }

# ── Tile ──────────────────────────────────────────────────────────────────────
echo "[webmap] Tiling (zoom 0-5) …"
mkdir -p "$TILES_OUT"
python3 /tile.py "$MAPS_TMP" "$TILES_OUT" 0 5

echo "[webmap] All done.  Tiles at $TILES_OUT"
