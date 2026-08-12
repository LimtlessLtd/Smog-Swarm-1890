"""Bakes fine-resolution per-hex land-cover tiles (playtest round 6, user
request: "fine detail everywhere but it's only rendered when you're
nearby based on the current tactical view system").

Writes one small PNG per hex coordinate to
res://assets/terrain_data/fine/<q>_<r>.png, at a MUCH finer
WORLD_UNITS_PER_PIXEL than bake_landcover.py's single whole-corridor
landcover.png (~10.7 world units/pixel, ~104 real metres/pixel, vs. the
coarse raster's ~90 world units/~878 metres) -- genuinely resolves
individual street blocks and field boundaries instead of an 878m/pixel
blur. RealTerrainSampler.gd's own "Fine per-hex tiles" section reads
these; a hex with no tile here just falls back to the coarse raster
exactly as before, so this is purely additive.

**Deliberately scoped to a demo radius around the starting settlement,
NOT the whole playable corridor**: baking street-level tiles for the
corridor's full ~50x75 hex extent (thousands of hexes) via this same
live-fetch pipeline would take many hours against the public Overpass
instance's own rate limits (a single bake_landcover.py corridor run
already needs dozens of retried 429/504s at the EXISTING coarse
resolution -- see that script's own bake session notes). This script
instead proves the pipeline genuinely works end-to-end for the area a
fresh campaign actually starts in, and is trivially re-runnable with a
different --center/--radius for the next region once the campaign
expands there (Act II Trent Valley, Act III London, ...) -- a mechanical
re-run, not a redesign, same "art/data lands incrementally" contract
bake_landcover.py's own corridor-vs-MAP_BOUNDS scope note already
established.

Reuses bake_landcover.py's own rasterize_features_onto_grid() (the exact
same two-pass area-then-waterway / core-vs-gap-fill-buffer logic, and
therefore the exact same round-6 water-over-coverage fix) rather than a
second, divergent rasterizer -- one fetch covering the whole demo hex
disk, then one small rasterize pass per hex, since fetch_bbox_tiled()
already tiles/caches/retries at a coarser granularity than "one hex" and
there is no reason to issue hundreds of tiny per-hex Overpass queries
when a handful of degree-scale tiles already cover the whole demo area.
"""

import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from geo_projection import CALIBRATION_POINTS, HEX_SIZE, axial_to_world, fit_affine, world_to_lonlat  # noqa: E402
from fetch_overpass import fetch_bbox_tiled  # noqa: E402
from bake_landcover import rasterize_features_onto_grid, lonlat_bbox_from_calibration_points  # noqa: E402
from png_codec import encode_png_rgb8  # noqa: E402

# --- Must match RealTerrainSampler.gd's WORLD_UNITS_PER_PIXEL_FINE exactly ---
FINE_TILE_PIXELS = 96
FINE_TILE_WORLD_SIZE = HEX_SIZE * 2.0  # Matches HexCoord.SUB_HEX_GRID_SPAN exactly -- see that constant's own doc comment for why this is the span sample_grid() needs covered.
FINE_WORLD_UNITS_PER_PIXEL = FINE_TILE_WORLD_SIZE / FINE_TILE_PIXELS

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data", "fine")

# Axial (q, r) for Manchester, same anchor bake_landcover.py's own --test
# mode uses ("Manchester's own world position").
DEFAULT_CENTER_Q = 80
DEFAULT_CENTER_R = 118


def hex_disk(center_q: int, center_r: int, radius: int) -> list[tuple[int, int]]:
    """Axial hex-disk enumeration -- same neighbor-direction shape
    HexCoord.hex_disk()/hex_ring() use, ported here so this script needs
    no Godot/GDScript runtime to enumerate the demo area."""
    directions = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
    coords = [(center_q, center_r)]
    for r in range(1, radius + 1):
        q, rr = center_q + directions[4][0] * r, center_r + directions[4][1] * r
        for i in range(6):
            for _ in range(r):
                coords.append((q, rr))
                q += directions[i][0]
                rr += directions[i][1]
    return coords


def bake_fine_tiles(center_q: int, center_r: int, radius: int):
    t0 = time.time()
    print(f"=== Fine tile bake: center=({center_q},{center_r}) radius={radius} ===")
    coords = hex_disk(center_q, center_r, radius)
    print(f"  {len(coords)} hexes in demo disk")

    print("=== Step 1: fit affine transform ===")
    transform = fit_affine(CALIBRATION_POINTS)

    print("=== Step 2: compute combined world-space extent for the whole disk ===")
    min_x = min_y = float("inf")
    max_x = max_y = float("-inf")
    half = FINE_TILE_WORLD_SIZE / 2.0
    for q, r in coords:
        wx, wy = axial_to_world(q, r)
        min_x = min(min_x, wx - half)
        max_x = max(max_x, wx + half)
        min_y = min(min_y, wy - half)
        max_y = max(max_y, wy + half)
    print(f"  world extent: x[{min_x:.0f},{max_x:.0f}] y[{min_y:.0f},{max_y:.0f}]")

    # Same "calibration points' own bbox, not the affine's amplified
    # inverse" reasoning bake_landcover.py's real (non-test) bake already
    # settled on -- but padded much tighter here (this demo area is a
    # couple of km across, not the whole corridor), so just derive a
    # small margin around the disk's own corners instead.
    from geo_projection import invert_affine
    inv_linear, offset = invert_affine(transform)
    corners = [(min_x, min_y), (max_x, min_y), (min_x, max_y), (max_x, max_y)]
    lonlats = [world_to_lonlat(inv_linear, offset, x, y) for x, y in corners]
    lons = [c[0] for c in lonlats]
    lats = [c[1] for c in lonlats]
    margin = 0.02
    lat_lo, lat_hi = min(lats) - margin, max(lats) + margin
    lon_lo, lon_hi = min(lons) - margin, max(lons) + margin
    print(f"  real lon/lat bbox: lat[{lat_lo:.3f},{lat_hi:.3f}] lon[{lon_lo:.3f},{lon_hi:.3f}]")

    print("=== Step 3: fetch OSM land-cover/water features (Overpass, tiled+cached) ===", flush=True)
    features = fetch_bbox_tiled(lat_lo, lon_lo, lat_hi, lon_hi, tile_degrees=0.5)

    print(f"=== Step 4: rasterize + write {len(coords)} fine tiles ===")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    written = 0
    for q, r in coords:
        cx, cy = axial_to_world(q, r)
        tile_min_x = cx - half
        tile_min_y = cy - half
        biome_grid = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS), dtype=np.uint8)
        feature_grid = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS), dtype=np.uint8)
        # Cheap pre-filter: only features whose own bbox could possibly
        # touch this one hex's tiny tile even get handed to the shared
        # rasterizer -- avoids re-scanning every OSM feature in the whole
        # demo area's fetch for every single hex.
        relevant = [
            f for f in features
            if _feature_might_touch(f, transform, tile_min_x, tile_min_y, FINE_TILE_WORLD_SIZE)
        ]
        rasterize_features_onto_grid(
            relevant, transform, tile_min_x, tile_min_y, FINE_WORLD_UNITS_PER_PIXEL,
            FINE_TILE_PIXELS, FINE_TILE_PIXELS, biome_grid, feature_grid,
        )
        rgb = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS, 3), dtype=np.uint8)
        rgb[:, :, 0] = biome_grid
        rgb[:, :, 1] = feature_grid
        path = os.path.join(OUTPUT_DIR, f"{q}_{r}.png")
        with open(path, "wb") as f:
            f.write(encode_png_rgb8(FINE_TILE_PIXELS, FINE_TILE_PIXELS, rgb.tobytes()))
        written += 1
        if written % 25 == 0:
            print(f"  {written}/{len(coords)} tiles written")

    print(f"  wrote {written} fine tiles to {OUTPUT_DIR}")
    print(f"  total time: {time.time() - t0:.1f}s")


def _feature_might_touch(feat, transform, tile_min_x, tile_min_y, tile_size, margin=200.0):
    from geo_projection import apply_affine
    ring = feat["ring"]
    # Cheap bbox check in lon/lat space would need the tile's own lon/lat
    # bbox recomputed per hex; simpler and just as cheap here to project
    # the (typically small) ring straight to world space and bbox-check --
    # rings are already small (a handful to a few hundred points), so this
    # is not the expensive part of the pipeline.
    world_ring = [apply_affine(transform, lon, lat) for lon, lat in ring]
    xs = [p[0] for p in world_ring]
    ys = [p[1] for p in world_ring]
    return not (max(xs) < tile_min_x - margin or min(xs) > tile_min_x + tile_size + margin or
                max(ys) < tile_min_y - margin or min(ys) > tile_min_y + tile_size + margin)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--center-q", type=int, default=DEFAULT_CENTER_Q)
    parser.add_argument("--center-r", type=int, default=DEFAULT_CENTER_R)
    parser.add_argument("--radius", type=int, default=8, help="hex-disk radius around the center to bake fine tiles for")
    args = parser.parse_args()
    bake_fine_tiles(args.center_q, args.center_r, args.radius)
