#!/usr/bin/env python3
"""
tile.py — Convert dmm-tools minimap output PNGs into an XYZ tile pyramid.

Usage:
    python3 tile.py <input_dir> <output_dir> [min_zoom] [max_zoom]

Input:
    PNGs named  <anything>-z<N>.png  (dmm-tools minimap output format).
    e.g.  hippiestation-z1.png, hippiestation-z2.png ...

Output layout (Leaflet XYZ, tms=false):
    <output_dir>/<z_level>/<zoom>/<tile_x>/<tile_y>.png

Coordinate system:
    For use with Leaflet L.CRS.Simple, bounds [[-256,0],[0,256]].
    At zoom Z there are 2^Z × 2^Z tiles, each 256×256 px.
    Tile (tx=0, ty=0) is top-left (northwest corner of the map).
    The source PNG must have its top edge = map north (highest BYOND Y).
    dmm-tools minimap already renders with Y=max at the top, so no flip needed.
"""

import sys
import os
import re
from pathlib import Path
from PIL import Image


TILE_SIZE = 256


def tile_image(src_path: Path, out_dir: Path, min_zoom: int, max_zoom: int):
    """Slice one flat PNG into XYZ tile pyramid levels min_zoom..max_zoom."""
    img = Image.open(src_path).convert("RGBA")
    print(f"  Source: {src_path.name}  ({img.width}×{img.height} px)")

    # Pad to a square whose side is a multiple of TILE_SIZE.
    # This ensures every zoom level divides evenly into 256-px tiles.
    side = max(img.width, img.height)
    side = ((side + TILE_SIZE - 1) // TILE_SIZE) * TILE_SIZE
    if img.width != side or img.height != side:
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(img, (0, 0))
        img = canvas

    for zoom in range(min_zoom, max_zoom + 1):
        num_tiles = 2 ** zoom          # tiles per axis at this zoom level
        target    = TILE_SIZE * num_tiles

        print(f"  zoom={zoom}: {num_tiles}×{num_tiles} tiles "
              f"(resizing to {target}×{target}) …", flush=True)

        scaled = img.resize((target, target), Image.LANCZOS)

        for tx in range(num_tiles):
            col_dir = out_dir / str(zoom) / str(tx)
            col_dir.mkdir(parents=True, exist_ok=True)
            for ty in range(num_tiles):
                tile = scaled.crop((
                    tx * TILE_SIZE,
                    ty * TILE_SIZE,
                    (tx + 1) * TILE_SIZE,
                    (ty + 1) * TILE_SIZE,
                ))
                tile.save(str(col_dir / f"{ty}.png"), optimize=True)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input_dir> <output_dir> [min_zoom] [max_zoom]")
        sys.exit(1)

    input_dir  = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    min_zoom   = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    max_zoom   = int(sys.argv[4]) if len(sys.argv) > 4 else 5

    # render.sh renames files to z<N>_level<M>.png before calling tile.py
    # e.g. z1_level1.png → tiles/1/  (game z-level 1 = station)
    #      z2_level1.png → tiles/2/  (game z-level 2 = lavaland)
    z_pattern = re.compile(r"^z(\d+)_level\d+\.png$", re.IGNORECASE)

    processed = 0
    for f in sorted(input_dir.iterdir()):
        m = z_pattern.match(f.name)
        if not m:
            continue
        z_level = m.group(1)
        z_out   = output_dir / z_level
        z_out.mkdir(parents=True, exist_ok=True)
        print(f"\nTiling z-level {z_level}: {f.name}")
        tile_image(f, z_out, min_zoom, max_zoom)
        processed += 1


    if processed == 0:
        print("\nERROR: No *-z<N>.png files found in", input_dir)
        print("Files present:", [x.name for x in input_dir.iterdir()])
        sys.exit(1)

    print(f"\nDone — tiled {processed} z-level(s) into {output_dir}")


if __name__ == "__main__":
    main()
