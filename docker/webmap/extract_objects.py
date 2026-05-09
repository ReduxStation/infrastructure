#!/usr/bin/env python3
"""
extract_objects.py — Build objects.json for one DMM, keyed by BYOND (x,y).

Pipeline:
    1. Walk the DM source tree, capture each /type's static `name` and `desc`
       initializers from the type body.
    2. Resolve inheritance: walk parent paths until a name/desc is found.
    3. Parse the TGM-format DMM:
        - header maps each "key" -> [type_path, ...]
        - body maps (x_start, 1, z) -> column of newline-separated keys
    4. Emit one entry per object on each tile, with name/desc/category.

The output JSON's "tiles" field is keyed by "x,y" (BYOND coords, 1-indexed).
The webmap frontend looks objects up by hashing pixel-derived (x,y) -- the
Leaflet pyramid pyramid (zoom/x/y) plays no role in object identity.
"""

import json
import os
import re
import sys
from pathlib import Path

# DM source roots that may contain type initializers.
# Skip _maps because DMMs declare instance overrides, not the type tree itself.
DM_DIRS = ["code"]

# Categories used by the webmap layer-filter checkboxes.
# First match wins; order matters.
CATEGORY_RULES = [
    ("/mob/", "mobs"),
    ("/obj/structure/cable", "cables-pipes"),
    ("/obj/machinery/atmospherics/pipe", "cables-pipes"),
    ("/obj/machinery/", "machines"),
    ("/obj/structure/", "structures"),
    ("/obj/item/", "items"),
    ("/turf/", "turfs"),
    ("/area/", "areas"),
]

# ----------------------------------------------------------------------------
# DM type tree: {type_path: {"name": ..., "desc": ...}}
# ----------------------------------------------------------------------------

# A type *definition* line is exactly /path/to/type at column 0, no parens.
# /path(args) is a proc, not a type definition. Operators / keywords filtered.
TYPE_DEF_RE = re.compile(r"^(/[\w/]+)\s*$")
# Indented vars: \tname = "value" or \tdesc = "value"
VAR_RE = re.compile(r'^\t(name|desc)\s*=\s*"((?:[^"\\]|\\.)*)"')


def categorize(type_path: str) -> str:
    for prefix, cat in CATEGORY_RULES:
        if type_path.startswith(prefix):
            return cat
    return "other"


def walk_dm_tree(src_root: Path):
    """Return {type_path: {"name": str|None, "desc": str|None}}."""
    types = {}
    current = None
    for dm_dir in DM_DIRS:
        root = src_root / dm_dir
        if not root.is_dir():
            continue
        for path in root.rglob("*.dm"):
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for raw in fh:
                        line = raw.rstrip("\n").rstrip("\r")
                        if not line:
                            current = None
                            continue
                        if line[0] == "/":
                            m = TYPE_DEF_RE.match(line)
                            if m:
                                current = m.group(1)
                                types.setdefault(current, {"name": None, "desc": None})
                            else:
                                current = None
                            continue
                        if line[0] not in (" ", "\t"):
                            current = None
                            continue
                        if current is None:
                            continue
                        m = VAR_RE.match(line)
                        if m and types[current][m.group(1)] is None:
                            types[current][m.group(1)] = m.group(2)
            except OSError:
                continue
    return types


def resolve(type_path: str, types: dict, field: str):
    """Walk parent paths until field is set. Returns "" if never resolved."""
    p = type_path
    while p and p != "/":
        info = types.get(p)
        if info and info.get(field):
            return info[field]
        idx = p.rfind("/")
        if idx <= 0:
            break
        p = p[:idx]
    return ""


# ----------------------------------------------------------------------------
# DMM parser (TGM format)
# ----------------------------------------------------------------------------

# Header lines: "key" = (
HEADER_KEY_RE = re.compile(r'^"([^"]+)"\s*=\s*\(\s*$')
# Each object inside a header tile is a /type, optionally followed by {props}
# and a trailing comma. We only need the type path itself.
HEADER_TYPE_RE = re.compile(r"^(/[\w/]+)")
# Body anchor: (x, y, z) = {"
BODY_ANCHOR_RE = re.compile(r"^\((\d+),(\d+),(\d+)\)\s*=\s*\{\"\s*$")


def parse_dmm(dmm_path: Path):
    """Return (key_to_types: dict, columns: list of (x_start, y_start, z, [keys])).

    columns is a list of column blocks; each block lists keys top-to-bottom
    (y from y_max downward).
    """
    key_to_types = {}
    columns = []

    with open(dmm_path, "r", encoding="utf-8", errors="replace") as fh:
        line = fh.readline()
        cur_key = None
        cur_types = []
        while line:
            stripped = line.rstrip("\n").rstrip("\r")
            if cur_key is not None:
                # In TGM, the closing ')' sits at the end of the last type's
                # line (e.g. "/area/space)") -- detect end-of-block by trailing
                # ')' rather than a line that begins with ')'.
                ends_block = stripped.rstrip().endswith(")")
                payload = stripped.rstrip()
                if ends_block:
                    payload = payload[:-1].rstrip().rstrip(",")
                # A line may contain just ")" (some emitters do split it onto
                # its own line) -- in which case payload is empty after strip.
                if payload:
                    m = HEADER_TYPE_RE.match(payload.lstrip())
                    if m:
                        cur_types.append(m.group(1))
                if ends_block:
                    key_to_types[cur_key] = cur_types
                    cur_key = None
                    cur_types = []
                line = fh.readline()
                continue
            m = HEADER_KEY_RE.match(stripped)
            if m:
                cur_key = m.group(1)
                cur_types = []
                line = fh.readline()
                continue
            m = BODY_ANCHOR_RE.match(stripped)
            if m:
                x_start = int(m.group(1))
                y_start = int(m.group(2))
                z = int(m.group(3))
                keys = []
                # Read until a line containing only "} or just "}
                while True:
                    nxt = fh.readline()
                    if not nxt:
                        break
                    s = nxt.rstrip("\n").rstrip("\r")
                    if s.startswith('"}'):
                        break
                    if s:
                        keys.append(s)
                columns.append((x_start, y_start, z, keys))
                line = fh.readline()
                continue
            line = fh.readline()

    return key_to_types, columns


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <src_root> <dmm_path> <output_json> <z_level>",
              file=sys.stderr)
        sys.exit(1)

    src_root = Path(sys.argv[1]).resolve()
    dmm_path = Path(sys.argv[2]).resolve()
    out_path = Path(sys.argv[3]).resolve()
    z_level = int(sys.argv[4])

    print(f"[extract_objects] DM source: {src_root}", flush=True)
    print(f"[extract_objects] DMM:       {dmm_path}", flush=True)

    print(f"[extract_objects] Walking DM tree …", flush=True)
    types = walk_dm_tree(src_root)
    print(f"[extract_objects]   captured {len(types):,} type definitions",
          flush=True)

    print(f"[extract_objects] Parsing DMM …", flush=True)
    key_to_types, columns = parse_dmm(dmm_path)
    print(f"[extract_objects]   {len(key_to_types):,} unique keys, "
          f"{len(columns):,} column blocks", flush=True)

    # Determine map extent. With TGM, max y per column == len(keys);
    # max x is max x_start across columns (each column block is 1 column wide).
    max_x = max((c[0] for c in columns), default=0)
    max_y = max((len(c[3]) for c in columns), default=0)
    print(f"[extract_objects]   extent: {max_x} × {max_y} BYOND tiles",
          flush=True)

    # Build (x,y) -> [type_path] from columns.
    tiles_out = {}
    for x_start, y_start, _z, keys in columns:
        # Keys are listed top-to-bottom; first key sits at y = y_start + len-1,
        # last sits at y = y_start. (TGM convention.)
        n = len(keys)
        for i, key in enumerate(keys):
            y = y_start + (n - 1 - i)
            x = x_start
            type_paths = key_to_types.get(key, [])
            entries = []
            for tp in type_paths:
                entries.append({
                    "type": tp,
                    "name": resolve(tp, types, "name"),
                    "desc": resolve(tp, types, "desc"),
                    "category": categorize(tp),
                })
            if entries:
                tiles_out[f"{x},{y}"] = entries

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({
            "z": z_level,
            "byond_width": max_x,
            "byond_height": max_y,
            "tiles": tiles_out,
        }, fh, separators=(",", ":"))

    print(f"[extract_objects] Wrote {out_path}  "
          f"({len(tiles_out):,} populated tiles)", flush=True)


if __name__ == "__main__":
    main()
