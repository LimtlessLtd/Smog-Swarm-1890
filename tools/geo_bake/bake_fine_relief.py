"""Bakes per-hex relief (hillshade) tiles at 30 m resolution.

Writes one greyscale PNG per hex to res://assets/terrain_data/relief/<q>_<r>.png,
geometrically identical to the land-cover fine tiles bake_fine_tiles.py writes
(FINE_TILE_PIXELS across FINE_TILE_WORLD_SIZE, centred on the hex), so the two
share one addressing scheme on the Godot side.

## Why this exists

"i still cannot clearly see elevation in the tactical view. things need to
actually look as though they are higher/lower in elevation than their
neighbours" (user report). The relief overlay that report was about reads
elevation from bake_landcover.py's whole-corridor elevation.png, and that
raster turned out to carry far less than it advertises:

  - it is written at WORLD_UNITS_PER_PIXEL (90 wu, ~878 m), but
  - its elevation step is `step = 4` with a NEAREST-NEIGHBOUR upsample, so
    the real sampling interval is ~3,510 m -- about 3x3 values per hex.

Measured on the shipped file: pixels at x%4 in {0,1,2} are identical to their
right neighbour 100% of the time. So the terracing visible in a hillshade
built from it is that upsample, not the source data, which at Terrarium z9 is
already ~180 m/px and at z12 is ~22.5 m/px.

This bake goes to the resolution the mechanical sub-hex grid already uses --
30 m, one value per HexCoord sub-cell -- which is ~333x333 per hex against
today's ~3x3.

## Why it stores SHADE, not metres

Two reasons, the second being the decisive one:

  - Size. One byte per pixel instead of Terrarium's three, before compression.
  - Seams. A hillshade is computed from the elevation GRADIENT, so a pixel's
    value depends on its neighbours. Computing it per tile at runtime would
    have to guess at values past each tile's own edge, and every tile boundary
    would show a discontinuity. Baking it here, from one continuous elevation
    field sampled with a margin around each tile, means the gradient at a
    tile's edge is taken from real neighbouring ground and adjacent tiles
    agree exactly.

Consequence, stated plainly: sub-hex elevation in METRES is still not stored
anywhere. Nothing needs it today (the mountain-impassability rule is per macro
hex, deliberately -- see SubHexPortalGraph._is_mountain_blocked()). If a
gameplay consumer ever does, the z12 tiles this fetches stay in cache/terrarium
and re-baking a metres channel from them is a small change, not a re-fetch.

## Shading

Neutral grey (128) is flat ground; lighter is lit, darker is in shade. The
overlay multiplies this over the terrain art, so a flat map stays exactly as
it looks today and only slopes are modulated.

Lit from the north-west, the cartographic convention -- relief lit from a
southerly direction reads INVERTED to most people (hills look like pits).

Usage:
    python bake_fine_relief.py --corridor
    python bake_fine_relief.py --center-q 80 --center-r 118 --radius 2
    python bake_fine_relief.py --center-q 80 --center-r 118 --radius 1 --estimate
"""

import argparse
import math
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from geo_projection import CALIBRATION_POINTS, HEX_SIZE, apply_affine, axial_to_world, fit_affine, invert_affine, world_to_lonlat  # noqa: E402
from bake_landcover import CORRIDOR_Q, CORRIDOR_R  # noqa: E402
from bake_fine_tiles import FINE_TILE_PIXELS, FINE_TILE_WORLD_SIZE, hex_disk  # noqa: E402
from png_codec import encode_png_gray8  # noqa: E402
import terrarium_mosaic  # noqa: E402

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data", "relief")

## z12 is ~22.5 m/px at GB latitude -- finer than the 30 m output grid, so the
## bake never upsamples the source. z11 (~45 m) would be the cheaper choice at
## a quarter the tiles, and is visually close for a hillshade; it is left as a
## flag rather than the default because "maximum detail" was the explicit call.
DEFAULT_ZOOM = 12

## Pixels of margin sampled around each tile before the gradient is taken, then
## discarded. One is the minimum a central difference needs; two keeps the
## smoothing pass below from reaching past real data at the edge.
_MARGIN_PX = 2

## Fixed light direction in tile-pixel space (+x right, +y down), north-west.
_LIGHT = np.array([-0.7071, -0.7071], dtype=np.float32)

## Metres of rise across one 30 m pixel that saturates the shading -- i.e. how
## much of the output range ORDINARY ground gets.
##
## Chosen by comparison, not by reasoning (tools/geo_bake/compare_relief_slope.py,
## which bakes one hex at several values side by side). The first bake used
## 12.0, a 40% grade that almost nothing in the corridor reaches, so every real
## British hillside landed in the bottom few percent of the range and the result
## read as a faint smudge over the terrain -- exactly the complaint this work
## exists to answer. Measured spread of the output byte on the hilliest sampled
## hex: 12.0 -> std 25.0, 8.0 -> 34.9, 5.0 -> 46.9, 3.5 -> 55.2, 2.0 -> 64.4.
##
## 3.5 m over 30 m is a ~12% grade: a real hillside, not a cliff. Below about
## 2.0 the shading saturates into flat black and white and stops describing
## shape at all, which the same comparison shows. The shader applies its own
## gains on top (assets/shaders/relief_hillshade.gdshader), so the on-screen
## effect is milder than the raw byte spread suggests.
_SLOPE_METRES_AT_FULL = 3.5

## How far shading may swing from neutral, in 0-255 units. Asymmetric because
## the eye reads darkening as depth more strongly than it reads brightening.
_SHADE_RANGE = 92.0
_LIGHT_RANGE = 66.0


def corridor_hexes() -> list[tuple[int, int]]:
    return [(q, r) for q in range(CORRIDOR_Q[0], CORRIDOR_Q[1] + 1)
            for r in range(CORRIDOR_R[0], CORRIDOR_R[1] + 1)]


def tile_origin_world(q: int, r: int) -> tuple[float, float]:
    """World position of a relief tile's top-left pixel, SNAPPED to a global
    sample lattice shared by every tile.

    A tile spans FINE_TILE_WORLD_SIZE (1024 wu) but hex centres are closer
    together than that, so neighbouring tiles overlap substantially. Left
    unsnapped, each tile's grid would start at its own hex centre minus half a
    span -- an arbitrary sub-pixel offset per tile -- so two tiles covering the
    same ground would sample the elevation field at slightly different points
    and disagree by a shade step or two. Drawn together that reads as a faint
    hex-shaped lattice over the whole map, which is precisely the artefact this
    whole line of work exists to remove.

    Snapping every origin down to a multiple of the pixel step makes all tiles
    subsets of ONE global lattice: overlapping pixels resolve to the identical
    world position, hence the identical elevation, gradient and output byte. The
    overlap becomes exact duplication and no seam can exist, whether the
    renderer clips tiles to their hex or simply overdraws them.

    Must match ReliefTileView's own origin calculation on the Godot side.
    """
    centre_x, centre_y = axial_to_world(q, r)
    step = FINE_TILE_WORLD_SIZE / FINE_TILE_PIXELS
    origin_x = math.floor((centre_x - FINE_TILE_WORLD_SIZE * 0.5) / step) * step
    origin_y = math.floor((centre_y - FINE_TILE_WORLD_SIZE * 0.5) / step) * step
    return origin_x, origin_y


def _tile_world_grid(q: int, r: int):
    """World-space x/y for every sampled pixel of one hex's tile, margin included."""
    origin_x, origin_y = tile_origin_world(q, r)
    size = FINE_TILE_PIXELS + 2 * _MARGIN_PX
    step = FINE_TILE_WORLD_SIZE / FINE_TILE_PIXELS
    # Pixel CENTRES, matching how RealTerrainSampler._sample_fine() addresses
    # the land-cover fine tiles (int(local / units_per_pixel) selects the pixel
    # a position falls inside, so the value belongs at that pixel's middle).
    offsets = (np.arange(size, dtype=np.float64) - _MARGIN_PX + 0.5) * step
    xs = origin_x + offsets
    ys = origin_y + offsets
    return np.meshgrid(xs, ys)


def _shade_from_metres(metres: np.ndarray, slope_full: float = _SLOPE_METRES_AT_FULL) -> np.ndarray:
    """Hillshade bytes for one tile, from its margin-padded elevation grid."""
    # Smooth once before differentiating. Terrarium quantises to 1/256 m but
    # its underlying SRTM-derived source is quantised far more coarsely than
    # that, and at 30 m spacing those steps are what a gradient operator would
    # otherwise turn into false micro-ridges.
    smoothed = metres.copy()
    smoothed[1:-1, :] = (metres[:-2, :] + metres[1:-1, :] + metres[2:, :]) / 3.0
    blurred = smoothed.copy()
    blurred[:, 1:-1] = (smoothed[:, :-2] + smoothed[:, 1:-1] + smoothed[:, 2:]) / 3.0

    # Central differences, then drop the margin.
    d_x = (blurred[:, 2:] - blurred[:, :-2]) * 0.5
    d_y = (blurred[2:, :] - blurred[:-2, :]) * 0.5
    d_x = d_x[_MARGIN_PX:-_MARGIN_PX or None, _MARGIN_PX - 1:(-_MARGIN_PX + 1) or None]
    d_y = d_y[_MARGIN_PX - 1:(-_MARGIN_PX + 1) or None, _MARGIN_PX:-_MARGIN_PX or None]

    lit = -(d_x * _LIGHT[0] + d_y * _LIGHT[1])
    strength = np.clip(lit / slope_full, -1.0, 1.0)
    shade = np.where(strength >= 0.0, strength * _LIGHT_RANGE, strength * _SHADE_RANGE)
    return np.clip(128.0 + shade, 0, 255).astype(np.uint8)


def _prefetch_for(coords: list[tuple[int, int]], zoom: int, inv_linear, offset, workers: int) -> None:
    """Warms the tile cache for every hex about to be baked, in parallel.

    Tile addresses are collected from each hex tile's four CORNERS rather than
    its full 337x337 sample grid: the grid is a rectangle in world space, its
    corners bound it, and every source tile it overlaps is inside that bound.
    Building the full grid for all 3,876 hexes just to enumerate tiles would
    cost more than the fetch it is planning.
    """
    print("=== Prefetching elevation tiles ===")
    half = FINE_TILE_WORLD_SIZE * 0.5
    corner_x = []
    corner_y = []
    for q, r in coords:
        cx, cy = axial_to_world(q, r)
        for dx in (-half, half):
            for dy in (-half, half):
                corner_x.append(cx + dx)
                corner_y.append(cy + dy)
    lon, lat = world_to_lonlat(inv_linear, offset, np.asarray(corner_x), np.asarray(corner_y))
    tiles = terrarium_mosaic.tiles_covering(lon, lat, zoom)
    # Corners bound each tile's extent, but a hex tile spans more than one
    # source tile, so the interior addresses between the corner tiles have to
    # be filled in as well.
    filled: set[tuple[int, int]] = set()
    xs = [t[0] for t in tiles]
    ys = [t[1] for t in tiles]
    if xs and ys:
        for x in range(min(xs), max(xs) + 1):
            for y in range(min(ys), max(ys) + 1):
                filled.add((x, y))
    terrarium_mosaic.prefetch(filled or tiles, zoom, workers)


def bake(coords: list[tuple[int, int]], zoom: int, force: bool, estimate_only: bool,
         workers: int = 16, slope_full: float = _SLOPE_METRES_AT_FULL,
         output_dir: str = OUTPUT_DIR) -> None:
    transform = fit_affine(CALIBRATION_POINTS)
    inv_linear, offset = invert_affine(transform)
    os.makedirs(output_dir, exist_ok=True)

    pending = [c for c in coords if force or not os.path.exists(os.path.join(output_dir, f"{c[0]}_{c[1]}.png"))]
    if pending:
        _prefetch_for(pending, zoom, inv_linear, offset, workers)
    print("=== Baking relief tiles ===")

    written = 0
    skipped = 0
    total_bytes = 0
    flat_tiles = 0
    started = time.time()
    last_print = started

    for index, (q, r) in enumerate(coords):
        path = os.path.join(output_dir, f"{q}_{r}.png")
        if not force and os.path.exists(path):
            skipped += 1
            continue

        world_x, world_y = _tile_world_grid(q, r)
        lon, lat = world_to_lonlat(inv_linear, offset, world_x, world_y)
        metres = terrarium_mosaic.sample_metres(np.asarray(lon), np.asarray(lat), zoom)
        shade = _shade_from_metres(metres, slope_full)

        # A tile whose ground is genuinely flat encodes to a single repeated
        # value. Counted rather than skipped: a missing tile means "fall back",
        # and silently omitting flat ground would make a bake failure and a
        # plain like the Fens indistinguishable on the Godot side.
        if int(shade.min()) == int(shade.max()):
            flat_tiles += 1

        png = encode_png_gray8(FINE_TILE_PIXELS, FINE_TILE_PIXELS, shade.tobytes())
        total_bytes += len(png)
        if not estimate_only:
            with open(path, "wb") as handle:
                handle.write(png)
        written += 1

        now = time.time()
        if now - last_print > 15:
            done = index + 1
            rate = written / max(now - started, 0.001)
            remaining = (len(coords) - done) / max(rate, 0.001)
            print(f"  {done}/{len(coords)} hexes  {rate:.1f}/s  ~{remaining / 60:.1f} min left  "
                  f"{total_bytes / 1e6:.1f} MB so far")
            last_print = now

    elapsed = time.time() - started
    fetch = terrarium_mosaic.stats()
    print()
    print(f"tiles written:      {written}" + ("  (ESTIMATE ONLY, nothing saved)" if estimate_only else ""))
    print(f"tiles skipped:      {skipped} (already present; pass --force to redo)")
    print(f"flat tiles:         {flat_tiles}")
    print(f"output size:        {total_bytes / 1e6:.1f} MB  ({total_bytes / max(written, 1) / 1024:.1f} KB/tile)")
    print(f"elapsed:            {elapsed / 60:.1f} min ({written / max(elapsed, 0.001):.1f} hexes/s)")
    print(f"terrarium z{zoom}:     {fetch['downloads']} downloaded, {fetch['failures']} unavailable")
    if written:
        per_hex = elapsed / written
        full = len(corridor_hexes())
        print(f"extrapolated to the full {full}-hex corridor: "
              f"{per_hex * full / 60:.0f} min, {total_bytes / written * full / 1e6:.0f} MB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corridor", action="store_true", help="bake the whole playable corridor")
    parser.add_argument("--center-q", type=int, default=80)
    parser.add_argument("--center-r", type=int, default=118)
    parser.add_argument("--radius", type=int, default=2)
    parser.add_argument("--zoom", type=int, default=DEFAULT_ZOOM,
                        help=f"terrarium source zoom (default {DEFAULT_ZOOM}, ~22.5 m/px; 11 is ~45 m/px and a quarter the tiles)")
    parser.add_argument("--force", action="store_true", help="rewrite tiles that already exist")
    parser.add_argument("--estimate", action="store_true",
                        help="do all the work but write nothing -- for measuring size/time before a full run")
    parser.add_argument("--slope-full", type=float, default=_SLOPE_METRES_AT_FULL,
                        help=f"metres of rise across one 30 m pixel that saturates the shading "
                             f"(default {_SLOPE_METRES_AT_FULL}); LOWER makes ordinary hillsides read more strongly")
    parser.add_argument("--out-dir", type=str, default=OUTPUT_DIR,
                        help="where to write tiles; point elsewhere to compare settings without touching the real bake")
    parser.add_argument("--workers", type=int, default=16,
                        help="concurrent tile downloads (default 16); the fetch is latency-bound, not bandwidth-bound")
    args = parser.parse_args()

    coords = corridor_hexes() if args.corridor else hex_disk(args.center_q, args.center_r, args.radius)
    print(f"baking relief for {len(coords)} hexes at z{args.zoom} "
          f"({FINE_TILE_PIXELS}x{FINE_TILE_PIXELS} per hex, "
          f"{FINE_TILE_WORLD_SIZE / FINE_TILE_PIXELS:.3f} wu/px)")
    bake(coords, args.zoom, args.force, args.estimate, args.workers, args.slope_full, args.out_dir)


if __name__ == "__main__":
    main()
