#!/bin/sh
# render.sh — Render + tile the HippieStation map on container startup.
#
# Renders three persistent z-levels:
#   z=1  hippiestation.dmm   (station + space + CentComm)
#   z=2  Lavaland.dmm        (mining / lavaland)
#   z=3  CentCom.dmm         (CentCom)
#
# For each z-level we produce:
#   - PNG tile pyramid:   $TILES_OUT/<z>/<zoom>/<x>/<y>.png   (Leaflet)
#   - Object index:       $TILES_OUT/<z>/objects.json         (BYOND-coord)
#
# A top-level manifest.json describes z-level names and the
# px-per-BYOND-tile constant the frontend needs for coord translation.
#
# To force a full re-render, remove the webmap_tiles volume:
#   docker volume rm <project>_webmap_tiles
#   docker-compose up webmap-renderer

set -e

TILES_OUT=/tiles/hippiestation
MAPS_TMP=/tmp/maps
SRC=/src

# dmm-tools minimap renders 32px per BYOND tile; the frontend hover-handler
# needs this constant to convert mouse pixel coords back to BYOND (x,y).
PX_PER_BYOND_TILE=32

# Z-level table:    game-z | dmm-path                                  | display name
Z_LEVELS="\
1|_maps/map_files/HippieStation/hippiestation.dmm|Station
2|_maps/map_files/Mining/Lavaland.dmm|Lavaland
3|_maps/map_files/generic/CentCom.dmm|CentCom"

# ── Skip if tiles already exist ───────────────────────────────────────────────
if [ -d "$TILES_OUT" ] && [ -f "$TILES_OUT/manifest.json" ]; then
    echo "[webmap] Tiles + manifest already present in $TILES_OUT — skipping render."
    echo "[webmap] Remove the webmap_tiles volume to force regeneration."
    exit 0
fi

mkdir -p "$MAPS_TMP" "$TILES_OUT"

# dmm-tools resolves #include paths relative to $CWD; must cd to source root.
cd "$SRC"

# ── Render PNG per z-level ────────────────────────────────────────────────────
echo "$Z_LEVELS" | while IFS='|' read -r Z DMM NAME; do
    [ -z "$Z" ] && continue
    echo "[webmap] Rendering z=$Z ($NAME) from $DMM …"
    dmm-tools minimap -o "$MAPS_TMP/" tgstation.dme "$DMM" 2>&1 \
        || echo "[webmap] Warning: dmm-tools returned non-zero (parse warnings are normal)"

    # dmm-tools names output <basename>-<level>.png; normalise to z<Z>_level<N>.png.
    base=$(basename "$DMM" .dmm)
    for f in "$MAPS_TMP/${base}"-*.png "$MAPS_TMP/$(echo "$base" | tr '[:upper:]' '[:lower:]')"-*.png; do
        [ -f "$f" ] || continue
        num=$(echo "$f" | grep -o '[0-9]*\.png$' | grep -o '[0-9]*')
        mv "$f" "$MAPS_TMP/z${Z}_level${num}.png"
    done
done

echo "[webmap] All rendered PNGs:"
ls "$MAPS_TMP"/*.png 2>/dev/null || { echo "[webmap] ERROR: No PNGs produced!"; exit 1; }

# ── Slice into Leaflet XYZ tile pyramid ──────────────────────────────────────
echo "[webmap] Tiling (zoom 0-5) …"
python3 /tile.py "$MAPS_TMP" "$TILES_OUT" 0 5

# ── Extract per-z objects.json (BYOND-coord-keyed metadata) ──────────────────
echo "[webmap] Extracting object metadata …"
echo "$Z_LEVELS" | while IFS='|' read -r Z DMM NAME; do
    [ -z "$Z" ] && continue
    OBJ_OUT="$TILES_OUT/$Z/objects.json"
    echo "[webmap] z=$Z → $OBJ_OUT"
    python3 /extract_objects.py "$SRC" "$SRC/$DMM" "$OBJ_OUT" "$Z" \
        || echo "[webmap] Warning: object extraction failed for z=$Z (frontend will degrade gracefully)"
done

# ── Top-level manifest.json (z-level catalogue + viewer constants) ───────────
echo "[webmap] Writing manifest.json …"
python3 - <<PYEOF
import json, os
from pathlib import Path

tiles_out = Path("$TILES_OUT")
z_levels = []
for line in """$Z_LEVELS""".strip().splitlines():
    z, _dmm, name = line.split("|", 2)
    z = int(z)
    obj_path = tiles_out / str(z) / "objects.json"
    byond_w = byond_h = 0
    if obj_path.is_file():
        try:
            with open(obj_path) as fh:
                data = json.load(fh)
            byond_w = int(data.get("byond_width", 0))
            byond_h = int(data.get("byond_height", 0))
        except (OSError, ValueError):
            pass
    z_levels.append({
        "id": z,
        "name": name,
        "byond_width": byond_w,
        "byond_height": byond_h,
    })

manifest = {
    "px_per_byond_tile": $PX_PER_BYOND_TILE,
    "tile_size": 256,
    "max_zoom": 5,
    "min_zoom": 0,
    "z_levels": z_levels,
}
with open(tiles_out / "manifest.json", "w") as fh:
    json.dump(manifest, fh, indent=2)
print(f"[webmap]   {len(z_levels)} z-level(s) catalogued")
PYEOF

echo "[webmap] All done.  Output at $TILES_OUT"
