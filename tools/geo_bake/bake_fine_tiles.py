"""Bakes fine-resolution per-hex land-cover tiles (playtest round 6, user
request: "fine detail everywhere but it's only rendered when you're
nearby based on the current tactical view system").

Writes one small PNG per hex coordinate to
res://assets/terrain_data/fine/<q>_<r>.png, at a MUCH finer
WORLD_UNITS_PER_PIXEL than bake_landcover.py's single whole-corridor
landcover.png (~104 real metres/pixel demo baseline, vs. the coarse
raster's ~90 world units/~878 metres) -- genuinely resolves individual
street blocks and field boundaries instead of an 878m/pixel blur.
RealTerrainSampler.gd's own "Fine per-hex tiles" section reads these; a
hex with no tile here just falls back to the coarse raster exactly as
before, so this is purely additive.

**Sub-Hex Mechanical Layer Phase 1b (todo.md, [[sub-hex-mechanical-layer-epic]]
memory)**: FINE_TILE_PIXELS is 333, matching HexCoord.SUB_HEX_GRID_N
exactly (ceili(HexCoord.SUB_HEX_GRID_SPAN / HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS),
Phase 1a) -- one baked pixel per 30m sub-hex cell, real 1:1 resolution,
not an approximation. Two bake modes:
- `--corridor`: the full 3,876-hex playable corridor (CORRIDOR_Q/CORRIDOR_R,
  imported from bake_landcover.py so the two scripts can't drift apart).
  Uses bake_landcover.py's own lonlat_bbox_from_calibration_points() as
  its Overpass query bbox -- the EXACT SAME bbox + tile_degrees=0.5 the
  coarse whole-corridor bake already used, so fetch_bbox_tiled()'s tile
  cache keys line up byte-for-byte and this mode fetches ZERO new
  Overpass tiles (confirmed: the coarse bake's own run already cached
  113 tiles / ~1.86M OSM elements covering this exact bbox) -- Phase 1b
  is a pure local CPU rasterization job, not a new network-bound one.
- `--center-q/--center-r/--radius` (original mode, kept): an arbitrary
  hex-disk demo region, for whichever area the campaign expands into
  next (Act II Trent Valley, Act III London, ...) without re-baking the
  whole corridor.

**Spatial feature index, not a per-hex O(all features) scan**: the
corridor's cached Overpass data is ~1.86M elements. The original per-hex
`_feature_might_touch()` filter looped over the ENTIRE fetched feature
list for every hex -- fine for the ~37-hex demo disk, intractable at
3,876 hexes (a naive scan would be ~3,876 x total-features affine-
projections). `_FeatureIndex` below projects each feature's ring to
world-space and buckets it into a coarse spatial grid ONCE, up front;
each hex then only scans the handful of buckets its own tile overlaps.

Reuses bake_landcover.py's own rasterize_features_onto_grid() (the exact
same two-pass area-then-waterway / core-vs-gap-fill-buffer logic, and
therefore the exact same round-6 water-over-coverage fix) rather than a
second, divergent rasterizer.
"""

import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from geo_projection import CALIBRATION_POINTS, HEX_SIZE, apply_affine, axial_to_world, fit_affine, invert_affine, world_to_lonlat  # noqa: E402
from fetch_overpass import fetch_bbox_tiled  # noqa: E402
from bake_landcover import (  # noqa: E402
    CORRIDOR_Q, CORRIDOR_R,
    lonlat_bbox_from_calibration_points,
    rasterize_features_onto_grid,
)
from png_codec import encode_png_rgb8  # noqa: E402

# --- Must match RealTerrainSampler.gd's WORLD_UNITS_PER_PIXEL_FINE exactly ---
# 333 = HexCoord.SUB_HEX_GRID_N (Phase 1a) -- one pixel per 30m mechanical
# sub-hex cell, not an arbitrary render-quality choice.
FINE_TILE_PIXELS = 333
FINE_TILE_WORLD_SIZE = HEX_SIZE * 2.0  # Matches HexCoord.SUB_HEX_GRID_SPAN exactly -- see that constant's own doc comment for why this is the span sample_grid() needs covered.
FINE_WORLD_UNITS_PER_PIXEL = FINE_TILE_WORLD_SIZE / FINE_TILE_PIXELS

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data", "fine")

# Axial (q, r) for Manchester, same anchor bake_landcover.py's own --test
# mode uses ("Manchester's own world position"). Only used by the
# hex-disk demo mode, not --corridor.
DEFAULT_CENTER_Q = 80
DEFAULT_CENTER_R = 118

# Spatial index bucket size -- one bucket per fine tile's own world
# footprint. Coarse enough that most hexes only touch a handful of
# buckets (not one bucket per 30m cell, which would just move the O(N)
# cost into building the index instead of querying it), fine enough that
# a bucket's own feature list stays small even in dense areas like
# central Manchester.
_BUCKET_SIZE = FINE_TILE_WORLD_SIZE


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


def corridor_hexes() -> list[tuple[int, int]]:
    """Every (q, r) in the full playable corridor rectangle -- 51 x 76 =
    3,876 hexes, matching RealTerrainSampler.gd's _CORRIDOR_Q/_CORRIDOR_R
    (both bounds inclusive, same convention as that Vector2i pair)."""
    return [(q, r) for q in range(CORRIDOR_Q[0], CORRIDOR_Q[1] + 1) for r in range(CORRIDOR_R[0], CORRIDOR_R[1] + 1)]


class _FeatureIndex:
    """Buckets every fetched OSM feature by its own projected world-space
    bbox, once, so a per-hex query only scans nearby buckets instead of
    the entire feature list. See this module's own doc comment for why
    this replaces the old per-hex full-list scan."""

    def __init__(self, features: list[dict], transform):
        self._buckets: dict[tuple[int, int], list[dict]] = {}
        t0 = time.time()
        for feat in features:
            world_ring = [apply_affine(transform, lon, lat) for lon, lat in feat["ring"]]
            xs = [p[0] for p in world_ring]
            ys = [p[1] for p in world_ring]
            min_bx = int(min(xs) // _BUCKET_SIZE)
            max_bx = int(max(xs) // _BUCKET_SIZE)
            min_by = int(min(ys) // _BUCKET_SIZE)
            max_by = int(max(ys) // _BUCKET_SIZE)
            for bx in range(min_bx, max_bx + 1):
                for by in range(min_by, max_by + 1):
                    self._buckets.setdefault((bx, by), []).append(feat)
        print(f"  spatial index: {len(features)} features -> {len(self._buckets)} buckets ({time.time() - t0:.1f}s)")

    def query(self, tile_min_x: float, tile_min_y: float, tile_size: float, margin: float = 200.0) -> list[dict]:
        min_bx = int((tile_min_x - margin) // _BUCKET_SIZE)
        max_bx = int((tile_min_x + tile_size + margin) // _BUCKET_SIZE)
        min_by = int((tile_min_y - margin) // _BUCKET_SIZE)
        max_by = int((tile_min_y + tile_size + margin) // _BUCKET_SIZE)
        seen_ids: set[int] = set()
        result = []
        for bx in range(min_bx, max_bx + 1):
            for by in range(min_by, max_by + 1):
                for feat in self._buckets.get((bx, by), []):
                    fid = id(feat)
                    if fid not in seen_ids:
                        seen_ids.add(fid)
                        result.append(feat)
        return result


def bake_fine_tiles(coords: list[tuple[int, int]], region_label: str, force: bool = False):
    t0 = time.time()
    print(f"=== Fine tile bake ({region_label}) ===")
    print(f"  {len(coords)} hexes")

    if not force:
        remaining = [(q, r) for q, r in coords if not os.path.exists(os.path.join(OUTPUT_DIR, f"{q}_{r}.png"))]
        skipped = len(coords) - len(remaining)
        if skipped:
            print(f"  {skipped} tiles already baked, resuming with {len(remaining)} remaining (pass --force to re-bake everything)")
        coords = remaining
    if not coords:
        print("  nothing to do")
        return

    print("=== Step 1: fit affine transform ===")
    transform = fit_affine(CALIBRATION_POINTS)

    print("=== Step 2: real lon/lat query bbox ===")
    # Corridor mode deliberately reuses bake_landcover.py's own
    # lonlat_bbox_from_calibration_points() verbatim (not a bbox derived
    # from this run's own hex coords) so fetch_bbox_tiled's tile
    # boundaries land on the exact same cache keys the coarse
    # whole-corridor bake already populated -- see this module's own doc
    # comment. The hex-disk demo mode keeps its own margin-based bbox
    # since it covers a different, smaller area than the corridor.
    if region_label == "corridor":
        lat_lo, lon_lo, lat_hi, lon_hi = lonlat_bbox_from_calibration_points()
    else:
        inv_linear, offset = invert_affine(transform)
        half = FINE_TILE_WORLD_SIZE / 2.0
        min_x = min_y = float("inf")
        max_x = max_y = float("-inf")
        for q, r in coords:
            wx, wy = axial_to_world(q, r)
            min_x, max_x = min(min_x, wx - half), max(max_x, wx + half)
            min_y, max_y = min(min_y, wy - half), max(max_y, wy + half)
        # Each hex's own CENTER goes through world_to_lonlat individually
        # (not a synthetic bounding-box corner, which can land far from
        # any calibration anchor and pick up amplified affine error) --
        # same reasoning bake_landcover.py's real corridor bake applies
        # via lonlat_bbox_from_calibration_points().
        lonlats = [world_to_lonlat(inv_linear, offset, *axial_to_world(q, r)) for q, r in coords]
        margin = 0.05  # a couple of hex-radii's worth of slack, real degrees at this latitude
        lat_lo = min(c[1] for c in lonlats) - margin
        lat_hi = max(c[1] for c in lonlats) + margin
        lon_lo = min(c[0] for c in lonlats) - margin
        lon_hi = max(c[0] for c in lonlats) + margin
    print(f"  real lon/lat bbox: lat[{lat_lo:.3f},{lat_hi:.3f}] lon[{lon_lo:.3f},{lon_hi:.3f}]")

    print("=== Step 3: fetch OSM land-cover/water features (Overpass, tiled+cached) ===", flush=True)
    features = fetch_bbox_tiled(lat_lo, lon_lo, lat_hi, lon_hi, tile_degrees=0.5)

    print("=== Step 4: build spatial feature index ===")
    index = _FeatureIndex(features, transform)

    print(f"=== Step 5: rasterize + write {len(coords)} fine tiles ===")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    written = 0
    half = FINE_TILE_WORLD_SIZE / 2.0
    for q, r in coords:
        cx, cy = axial_to_world(q, r)
        tile_min_x = cx - half
        tile_min_y = cy - half
        biome_grid = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS), dtype=np.uint8)
        feature_grid = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS), dtype=np.uint8)
        relevant = index.query(tile_min_x, tile_min_y, FINE_TILE_WORLD_SIZE)
        # core_buffer_fraction=0.35 (opt-in, unlike the coarse whole-
        # corridor bake's own default-0.0 call) -- at this raster's much
        # finer real-30m pixels, "a river genuinely crossing a city block
        # should still show as water" is a proportionally small,
        # legitimate nuance instead of the dominant source of over-
        # marking it turned out to be at the coarse raster's ~878m/pixel
        # -- see bake_landcover.py's own rasterize_features_onto_grid()
        # doc comment for the measured history of why the coarse bake
        # dropped this same idea entirely.
        rasterize_features_onto_grid(
            relevant, transform, tile_min_x, tile_min_y, FINE_WORLD_UNITS_PER_PIXEL,
            FINE_TILE_PIXELS, FINE_TILE_PIXELS, biome_grid, feature_grid,
            core_buffer_fraction=0.35,
        )
        rgb = np.zeros((FINE_TILE_PIXELS, FINE_TILE_PIXELS, 3), dtype=np.uint8)
        rgb[:, :, 0] = biome_grid
        rgb[:, :, 1] = feature_grid
        path = os.path.join(OUTPUT_DIR, f"{q}_{r}.png")
        with open(path, "wb") as f:
            f.write(encode_png_rgb8(FINE_TILE_PIXELS, FINE_TILE_PIXELS, rgb.tobytes()))
        written += 1
        if written % 25 == 0:
            elapsed = time.time() - t0
            rate = written / elapsed
            eta = (len(coords) - written) / rate if rate > 0 else float("inf")
            print(f"  {written}/{len(coords)} tiles written ({elapsed:.0f}s elapsed, ETA {eta / 60:.0f}min)", flush=True)

    print(f"  wrote {written} fine tiles to {OUTPUT_DIR}")
    print(f"  total time: {time.time() - t0:.1f}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--corridor", action="store_true", help="bake the full 3,876-hex playable corridor (CORRIDOR_Q/CORRIDOR_R) instead of a hex-disk demo region")
    parser.add_argument("--center-q", type=int, default=DEFAULT_CENTER_Q)
    parser.add_argument("--center-r", type=int, default=DEFAULT_CENTER_R)
    parser.add_argument("--radius", type=int, default=3, help="hex-disk radius around the center to bake fine tiles for (each hex is ~5km real circumradius -- radius 3 already spans ~30km, plenty for a starting-area demo; keep this small, it's an Overpass query area, not a hex count). Ignored with --corridor.")
    parser.add_argument("--force", action="store_true", help="re-bake tiles that already exist on disk (default: skip them, resumable)")
    args = parser.parse_args()
    if args.corridor:
        bake_fine_tiles(corridor_hexes(), "corridor", force=args.force)
    else:
        bake_fine_tiles(hex_disk(args.center_q, args.center_r, args.radius), "demo", force=args.force)
