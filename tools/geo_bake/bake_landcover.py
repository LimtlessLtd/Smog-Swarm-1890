"""Orchestrator: bake real land-cover + elevation rasters covering the
game's existing hex map extent, from real open data (OpenStreetMap
Overpass + AWS/Mapzen Terrain Tiles).

Deliberately does NOT touch BritishGeographyData.gd's existing
_LAND_RLE/MAP_BOUNDS/_build_features() coastline+feature data at all --
those already encode the correct real coastline shape (just under a
lost original transform) and nothing outside this file's own fitted
affine needs to know the old transform's exact numbers. This script's
fitted affine is used purely to translate between the EXISTING hex
world-space (unchanged) and real lon/lat, so real OSM/elevation data can
be sampled for whatever the map already looks like today. That's a
materially lower-risk design than re-deriving the coastline shape itself
-- confirmed safe via the calibration residual check in
geo_projection.py (the 3 verified city anchors land within ~2.4 hex
radii, most of the 21 calibration points within 1-3).

Output: two PNGs, pixel-aligned to world-space via a simple linear
formula (RASTER_ORIGIN_WORLD + pixel_index * WORLD_UNITS_PER_PIXEL),
written to res://assets/terrain_data/. RealTerrainSampler.gd (GDScript)
must use the EXACT SAME WORLD_UNITS_PER_PIXEL/RASTER_ORIGIN_WORLD
constants to invert the mapping at runtime -- documented cross-
reference, same "shared derivation, don't hand-copy" convention
HexCoord.WORLD_UNITS_PER_REAL_METER already established in this project.

Wire format (deliberately decoupled from GameEnums.BiomeType's raw
ordinals, which have been reordered before and must never silently
corrupt baked data if reordered again):
  landcover.png:
    R = biome code   (0=MOORLAND,1=FARMLAND,2=URBAN,3=INDUSTRIAL,
                       4=WETLAND,5=WATERWAY,6=HIGHLAND)
    G = terrain_feature code (0=NONE,1=RIVER,2=CANAL,3=MARSH,
                               4=PEAT_BOG,5=ESCARPMENT)
    B = 0 (reserved)
  elevation.png: Terrarium RGB encoding of real elevation in metres
    (elevation = R*256 + G + B/256 - 32768), same scheme as the source
    Terrain Tiles data -- no reason to invent a different one.
"""

import argparse
import math
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from geo_projection import CALIBRATION_POINTS, HEX_SIZE, axial_to_world, fit_affine, invert_affine, world_to_lonlat  # noqa: E402
from fetch_overpass import fetch_bbox_tiled  # noqa: E402
from fetch_terrarium import terrarium_elevation_at  # noqa: E402
from png_codec import encode_png_rgb8  # noqa: E402

# --- Must match RealTerrainSampler.gd exactly ---
# 90 world units/pixel ~= 878 real metres/pixel (HexCoord.WORLD_UNITS_PER_REAL_METER
# = 0.1025599 world units/metre) -- gives ~9.8 pixels across one hex's
# flat-to-flat width (HEX_SIZE*sqrt(3) ~= 886.8 world units), enough real
# variation for the 5x5/7x7 sub-hex sample grids without an unreasonably
# large raster or bake runtime.
WORLD_UNITS_PER_PIXEL = 90.0
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data")

# Existing BritishGeographyData.MAP_BOUNDS (scripts/world/data/BritishGeographyData.gd) --
# unchanged by this pass, just read here to know the world-space extent to cover.
MAP_BOUNDS_Q = (0, 154)
MAP_BOUNDS_R = (0, 179)

# Deliberate, disclosed scope reduction for this pass: bake real terrain
# data for the actually-PLAYABLE core corridor (Manchester/Midlands/
# London, comfortably covering every calibration anchor with margin) --
# NOT the full 154x179 MAP_BOUNDS, most of which is Wales/Scotland/
# Ireland: hard-gated, zero authored content, not reachable in the
# current build (Phase 7.2.1). RealTerrainSampler gracefully falls back
# to the old flat default for any hex outside this baked coverage, so
# nothing regresses for the locked regions -- they're exactly as
# data-poor as they already were, not worse. Extending real coverage to
# those regions once they get real campaign content (Phase 7.4/7.5) is a
# straightforward re-run of this same script with a wider range, not a
# redesign.
CORRIDOR_Q = (55, 105)
CORRIDOR_R = (85, 160)

HIGHLAND_ELEVATION_THRESHOLD_M = 175.0

_BIOME_CODE = {
    "MOORLAND": 0, "FARMLAND": 1, "URBAN": 2, "INDUSTRIAL": 3,
    "WETLAND": 4, "WATERWAY": 5, "HIGHLAND": 6,
    # Granularity pass (2026-08-11): appended, not inserted — codes 0-6 are
    # already baked into committed landcover.png bytes; renumbering would
    # silently reclassify every existing pixel. Must match
    # RealTerrainSampler.gd's _BIOME_BY_CODE array index-for-index (same
    # "decoupled from GameEnums ordinals, append-only" contract this dict
    # already documents above).
    "WOODLAND": 7, "HEATHLAND": 8,
}
_FEATURE_CODE = {"NONE": 0, "RIVER": 1, "CANAL": 2, "MARSH": 3, "PEAT_BOG": 4, "ESCARPMENT": 5}

_LANDUSE_MAP = {
    "forest": "WOODLAND", "farmland": "FARMLAND", "orchard": "FARMLAND",
    "meadow": "FARMLAND", "allotments": "FARMLAND", "farmyard": "FARMLAND",
    "residential": "URBAN", "commercial": "URBAN", "retail": "URBAN", "construction": "URBAN",
    "industrial": "INDUSTRIAL",
}
_NATURAL_MAP = {
    # Granularity pass (2026-08-11): wood/heath/scrub used to all funnel
    # into MOORLAND alongside genuine open grazing land — real, distinct
    # UK landscape types (forest cover vs. heather/gorse scrubland vs. open
    # moor) were being flattened into one catch-all despite the tags to
    # tell them apart already being fetched from Overpass. No new query
    # needed, just using data that was already being thrown away.
    "wood": "WOODLAND", "wetland": "WETLAND", "heath": "HEATHLAND",
    "water": "WATERWAY", "scrub": "HEATHLAND",
}
_WATERWAY_FEATURE = {"river": "RIVER", "canal": "CANAL", "stream": "RIVER"}


def world_extent_corners(q_range=MAP_BOUNDS_Q, r_range=MAP_BOUNDS_R):
    corners = []
    for q in q_range:
        for r in r_range:
            corners.append(axial_to_world(q, r))
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    return min(xs), min(ys), max(xs), max(ys)


def lonlat_bbox_for_world_extent(inv_linear, offset, min_x, min_y, max_x, max_y, margin_frac=0.03):
    """DELIBERATELY UNUSED for the real (non-test) bake -- see the caller's
    own comment for why. Kept for the small --test window (a tiny
    rectangle right at the calibration cluster's own center, where the
    fit's imprecision doesn't get a chance to amplify)."""
    dx = (max_x - min_x) * margin_frac
    dy = (max_y - min_y) * margin_frac
    corners = [
        world_to_lonlat(inv_linear, offset, min_x - dx, min_y - dy),
        world_to_lonlat(inv_linear, offset, max_x + dx, min_y - dy),
        world_to_lonlat(inv_linear, offset, min_x - dx, max_y + dy),
        world_to_lonlat(inv_linear, offset, max_x + dx, max_y + dy),
    ]
    lons = [c[0] for c in corners]
    lats = [c[1] for c in corners]
    return min(lats), min(lons), max(lats), max(lons)


def lonlat_bbox_from_calibration_points(margin_deg=0.6):
    """Real bake's query-bbox source of truth: the CALIBRATION points'
    own real, directly-input lon/lat range (padded by a fixed margin),
    NOT the affine's inverse applied to a big world-space rectangle.

    Found and fixed during this bake session: inverting a ~78,000 x
    58,000 world-unit rectangle's 4 corners through the fitted affine
    amplified the fit's own real (if modest, a few hex-radii per point)
    imprecision into a wildly oversized lon/lat bbox -- lon -8.6..4.7,
    lat 50.5..55.7, reaching into the Atlantic west of Ireland and the
    North Sea past the Netherlands, nothing like the actual English
    corridor intended. The calibration points' own coordinates carry no
    such amplification (they're real input data, not something derived
    through the fit's own error), so their bounding box is the reliable
    source of truth for "what real area does this bake actually need,"
    even though the SAME fitted transform is still exactly right for its
    real job: converting one specific pixel's world position to lon/lat
    for classification, a local (not corner-to-corner-of-a-huge-
    rectangle) operation where the fit's error stays small.
    """
    lons = [p[1] for p in CALIBRATION_POINTS]
    lats = [p[2] for p in CALIBRATION_POINTS]
    return min(lats) - margin_deg, min(lons) - margin_deg, max(lats) + margin_deg, max(lons) + margin_deg


def point_in_ring(px: float, py: float, ring: list[tuple[float, float]]) -> bool:
    """Even-odd point-in-polygon test, single point (used only for the
    tiny validation run below -- the full bake uses the vectorized
    per-row version in rasterize_polygons)."""
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if ((y1 > py) != (y2 > py)) and (px < (x2 - x1) * (py - y1) / (y2 - y1 + 1e-12) + x1):
            inside = not inside
    return inside


def rasterize_features_onto_grid(features, transform, grid_min_x, grid_min_y, px_size,
                                  grid_w, grid_h, biome_grid, feature_grid):
    """For each OSM feature (way/relation ring in lon/lat), project its
    points to world-space, find its own pixel-space bbox, and only test
    pixels inside that bbox -- avoids an O(pixels x features) blowup.
    Vectorized per-feature with numpy (bbox-limited, so each call is
    cheap even though there may be thousands of features total).

    **Real bug fix (playtest round 6, user report: "the water sub hex
    tiles... central Manchester seems to be covered in water for some
    reason"):** two compounding problems, both fixed here.

    1. AREA polygons (landuse/natural -- real, solid ground
       classifications) and WATERWAY lines used to be rasterized in
       whatever order Overpass happened to return them in (`features`'
       own iteration order, effectively random per bake run), each
       unconditionally overwriting the other wherever they overlapped --
       so a dense city centre criss-crossed by several named
       watercourses (the Irwell/Irk/Medlock plus canal branches, all
       within a couple of real kilometres of each other in central
       Manchester) could have its own URBAN polygon classification
       stomped by a LATER-processed river/stream buffer, or vice versa,
       non-deterministically. Fixed by processing every AREA feature
       FIRST (a real, explicit ground-truth polygon), THEN every
       WATERWAY line -- see the two-pass split below.

    2. Even with that ordering fixed, the waterway buffer itself
       (`GAP_FILL_BUFFER_FRACTION`, unconditional) is still generous
       enough by design (see its own comment -- "guarantee no gaps
       between pixels along the line's own path") that a pixel merely
       NEAR a watercourse, not actually on it, still got flagged WATER --
       fine out in open countryside (nothing else was competing for that
       pixel anyway), wrong in a dense urban core where that same pixel
       is very likely genuinely dry, real, buildable city ground. Split
       into two tiers: a tight CORE buffer (this pixel basically IS the
       channel -- always wins, even over URBAN/INDUSTRIAL, since a real
       river running through a city centre SHOULD read as a visible
       ribbon of water through the urban texture) and the wider GAP-FILL
       buffer (this pixel is merely near a watercourse -- only wins if
       nothing has already classified this exact pixel as URBAN or
       INDUSTRIAL; still wins over the default MOORLAND/whatever-else so
       thin rivers through open countryside don't develop gaps).
    """
    from geo_projection import apply_affine

    CORE_BUFFER_FRACTION = 0.35    ## "this pixel basically IS the channel" -- always wins.
    GAP_FILL_BUFFER_FRACTION = 0.6  ## "merely near a watercourse" -- wins only over non-built-up ground; see this function's own doc comment, item 2.
    _URBAN_LIKE_CODES = (_BIOME_CODE["URBAN"], _BIOME_CODE["INDUSTRIAL"])

    n_polygons = n_lines = 0

    # Pass 1: every AREA feature (landuse/natural polygons) -- real ground
    # classification, processed before any waterway line can compete with it.
    for feat in features:
        tags = feat["tags"]
        if tags.get("waterway"):
            continue
        landuse = tags.get("landuse")
        natural = tags.get("natural")
        biome = _LANDUSE_MAP.get(landuse) or _NATURAL_MAP.get(natural)
        if not biome:
            continue

        ring = feat["ring"]
        world_ring = [apply_affine(transform, lon, lat) for lon, lat in ring]
        xs = [p[0] for p in world_ring]
        ys = [p[1] for p in world_ring]
        min_px = max(0, int((min(xs) - grid_min_x) / px_size))
        max_px = min(grid_w - 1, int((max(xs) - grid_min_x) / px_size))
        min_py = max(0, int((min(ys) - grid_min_y) / px_size))
        max_py = min(grid_h - 1, int((max(ys) - grid_min_y) / px_size))
        if min_px > max_px or min_py > max_py:
            continue
        sub_w = max_px - min_px + 1
        sub_h = max_py - min_py + 1
        if sub_w * sub_h > 4_000_000:
            continue  # a mis-tagged continent-spanning "polygon" -- skip defensively
        xs_grid = grid_min_x + (min_px + np.arange(sub_w)) * px_size
        ys_grid = grid_min_y + (min_py + np.arange(sub_h)) * px_size
        gx, gy = np.meshgrid(xs_grid, ys_grid)
        inside = np.zeros(gx.shape, dtype=bool)
        n = len(world_ring)
        for i in range(n):
            x1, y1 = world_ring[i]
            x2, y2 = world_ring[(i + 1) % n]
            cond = (y1 > gy) != (y2 > gy)
            with np.errstate(divide="ignore", invalid="ignore"):
                x_intersect = (x2 - x1) * (gy - y1) / (y2 - y1 + 1e-12) + x1
            cross = cond & (gx < x_intersect)
            inside ^= cross
        sub_biome = biome_grid[min_py:min_py + sub_h, min_px:min_px + sub_w]
        sub_feat = feature_grid[min_py:min_py + sub_h, min_px:min_px + sub_w]
        sub_biome[inside] = _BIOME_CODE[biome]
        sub_feat[inside & (sub_feat == 0)] = _FEATURE_CODE["NONE"]
        n_polygons += 1

    # Pass 2: every WATERWAY line, now that every real polygon
    # classification already sits in biome_grid/feature_grid.
    for feat in features:
        tags = feat["tags"]
        waterway = tags.get("waterway")
        if not waterway:
            continue

        ring = feat["ring"]
        world_ring = [apply_affine(transform, lon, lat) for lon, lat in ring]
        # Line feature -- buffered by just enough to guarantee no gaps
        # between pixels along the line's own path (a real river/
        # stream corridor, ~10-100m, is sub-pixel at this raster's
        # resolution anyway -- the buffer's job is rasterization
        # correctness, not modelling true real-world width. A prior
        # version of this buffer was set to 120 world units thinking
        # it meant "~120 real metres" -- it actually meant ~1170
        # real metres (see WORLD_UNITS_PER_REAL_METER), which
        # over-marked roughly half the pixels in a validation run as
        # WATERWAY. Fixed by deriving the buffer from pixel size
        # instead of hand-guessing a real-world distance -- see this
        # function's own doc comment, item 2, for the two-tier split.
        biome = "WATERWAY"
        terrain_feature = _WATERWAY_FEATURE.get(waterway, "RIVER")
        gap_fill_buffer = WORLD_UNITS_PER_PIXEL * GAP_FILL_BUFFER_FRACTION
        core_buffer = WORLD_UNITS_PER_PIXEL * CORE_BUFFER_FRACTION
        xs = [p[0] for p in world_ring]
        ys = [p[1] for p in world_ring]
        min_px = max(0, int((min(xs) - gap_fill_buffer - grid_min_x) / px_size))
        max_px = min(grid_w - 1, int((max(xs) + gap_fill_buffer - grid_min_x) / px_size))
        min_py = max(0, int((min(ys) - gap_fill_buffer - grid_min_y) / px_size))
        max_py = min(grid_h - 1, int((max(ys) + gap_fill_buffer - grid_min_y) / px_size))
        if min_px > max_px or min_py > max_py:
            continue
        sub_w = max_px - min_px + 1
        sub_h = max_py - min_py + 1
        xs_grid = grid_min_x + (min_px + np.arange(sub_w)) * px_size
        ys_grid = grid_min_y + (min_py + np.arange(sub_h)) * px_size
        gx, gy = np.meshgrid(xs_grid, ys_grid)
        min_dist = np.full(gx.shape, np.inf)
        for i in range(len(world_ring) - 1):
            x1, y1 = world_ring[i]
            x2, y2 = world_ring[i + 1]
            seg = np.array([x2 - x1, y2 - y1])
            seg_len2 = seg[0] ** 2 + seg[1] ** 2
            if seg_len2 < 1e-9:
                continue
            t = ((gx - x1) * seg[0] + (gy - y1) * seg[1]) / seg_len2
            t = np.clip(t, 0.0, 1.0)
            proj_x = x1 + t * seg[0]
            proj_y = y1 + t * seg[1]
            dist = np.hypot(gx - proj_x, gy - proj_y)
            min_dist = np.minimum(min_dist, dist)
        sub_biome = biome_grid[min_py:min_py + sub_h, min_px:min_px + sub_w]
        sub_feat = feature_grid[min_py:min_py + sub_h, min_px:min_px + sub_w]
        core_mask = min_dist <= core_buffer
        gap_fill_mask = (min_dist <= gap_fill_buffer) & ~np.isin(sub_biome, _URBAN_LIKE_CODES)
        mask = core_mask | gap_fill_mask
        sub_biome[mask] = _BIOME_CODE[biome]
        sub_feat[mask] = _FEATURE_CODE[terrain_feature]
        n_lines += 1

    print(f"  rasterized {n_polygons} area features + {n_lines} line features")


def bake(test_mode: bool = False):
    t0 = time.time()
    print("=== Step 1: fit affine transform ===")
    transform = fit_affine(CALIBRATION_POINTS)
    inv_linear, offset = invert_affine(transform)

    print("=== Step 2: compute world-space extent + real lon/lat bbox ===")
    min_x, min_y, max_x, max_y = world_extent_corners(CORRIDOR_Q, CORRIDOR_R)
    if test_mode:
        # Small validation window centred on Manchester's own world position.
        cx, cy = axial_to_world(80, 118)
        half = 3000.0  # world units, a handful of hexes
        min_x, min_y, max_x, max_y = cx - half, cy - half, cx + half, cy + half
    print(f"  world extent: x[{min_x:.0f},{max_x:.0f}] y[{min_y:.0f},{max_y:.0f}]")
    if test_mode:
        lat_lo, lon_lo, lat_hi, lon_hi = lonlat_bbox_for_world_extent(inv_linear, offset, min_x, min_y, max_x, max_y)
    else:
        # See lonlat_bbox_from_calibration_points()'s own doc comment --
        # NOT derived from inverse-transforming this rectangle's corners,
        # which amplified the affine fit's real (if modest per-point)
        # imprecision into a wildly oversized bbox reaching into the
        # Atlantic and the North Sea during this same bake session.
        lat_lo, lon_lo, lat_hi, lon_hi = lonlat_bbox_from_calibration_points()
    print(f"  real lon/lat bbox: lat[{lat_lo:.3f},{lat_hi:.3f}] lon[{lon_lo:.3f},{lon_hi:.3f}]")

    grid_w = max(1, int((max_x - min_x) / WORLD_UNITS_PER_PIXEL))
    grid_h = max(1, int((max_y - min_y) / WORLD_UNITS_PER_PIXEL))
    print(f"  raster size: {grid_w} x {grid_h} = {grid_w * grid_h:,} pixels")

    print("=== Step 3: fetch OSM land-cover/water features (Overpass, tiled+cached) ===", flush=True)
    # 0.5 degrees, not the original 1.0 -- this bake session found the
    # public Overpass instance intermittently returning 429/504 on the
    # bigger city-dense tiles (Manchester/Birmingham/London all have a
    # LOT of landuse polygons), sometimes stalling for minutes on a
    # single stubborn 1-degree tile. Smaller queries are both faster
    # individually and fail (and get retried/skipped) faster when they do.
    tile_deg = 0.5 if not test_mode else 0.3
    features = fetch_bbox_tiled(lat_lo, lon_lo, lat_hi, lon_hi, tile_degrees=tile_deg)

    print("=== Step 4: rasterize OSM features onto the grid ===")
    biome_grid = np.zeros((grid_h, grid_w), dtype=np.uint8)  # default MOORLAND (code 0)
    feature_grid = np.zeros((grid_h, grid_w), dtype=np.uint8)  # default NONE (code 0)
    rasterize_features_onto_grid(features, transform, min_x, min_y, WORLD_UNITS_PER_PIXEL,
                                  grid_w, grid_h, biome_grid, feature_grid)

    print("=== Step 5: sample real elevation, apply highland override ===")
    elev_grid = np.zeros((grid_h, grid_w), dtype=np.float32)
    # Elevation sampling is the expensive step (one Terrarium tile fetch
    # per distinct z9 tile touched, cached) -- sample on a coarser
    # sub-grid and upsample, since elevation varies smoothly at the
    # Terrarium source's own ~180m/px resolution anyway.
    step = 4 if not test_mode else 1
    sampled_rows = list(range(0, grid_h, step))
    sampled_cols = list(range(0, grid_w, step))
    coarse = np.zeros((len(sampled_rows), len(sampled_cols)), dtype=np.float32)
    total = len(sampled_rows) * len(sampled_cols)
    done = 0
    last_print = time.time()
    for i, py in enumerate(sampled_rows):
        wy = min_y + py * WORLD_UNITS_PER_PIXEL
        for j, px in enumerate(sampled_cols):
            wx = min_x + px * WORLD_UNITS_PER_PIXEL
            lon, lat = world_to_lonlat(inv_linear, offset, wx, wy)
            coarse[i, j] = terrarium_elevation_at(lon, lat)
            done += 1
        if time.time() - last_print > 15:
            print(f"  elevation sampling: {done}/{total} ({100 * done / total:.1f}%)")
            last_print = time.time()
    # Nearest-neighbour upsample back to full grid.
    row_idx = np.clip(np.arange(grid_h) // step, 0, len(sampled_rows) - 1)
    col_idx = np.clip(np.arange(grid_w) // step, 0, len(sampled_cols) - 1)
    elev_grid = coarse[np.ix_(row_idx, col_idx)]

    highland_mask = elev_grid > HIGHLAND_ELEVATION_THRESHOLD_M
    # Highland override applies UNDER explicit water/wetland classification
    # (a river running through a valley shouldn't become "highland" just
    # because the surrounding hillside is high) but OVER default MOORLAND.
    # WOODLAND/HEATHLAND included alongside MOORLAND/FARMLAND — before this
    # pass, wood/heath/scrub pixels WERE classified MOORLAND and so WERE
    # already eligible for this override; keeping them eligible now that
    # they're distinct codes preserves that behavior rather than silently
    # dropping it (real elevated forestry/heath moor both genuinely exist).
    override_mask = highland_mask & np.isin(biome_grid, [
        _BIOME_CODE["MOORLAND"], _BIOME_CODE["FARMLAND"],
        _BIOME_CODE["WOODLAND"], _BIOME_CODE["HEATHLAND"],
    ])
    biome_grid[override_mask] = _BIOME_CODE["HIGHLAND"]
    feature_grid[override_mask] = _FEATURE_CODE["ESCARPMENT"]

    print("=== Step 6: write baked PNGs ===")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    landcover_rgb = np.zeros((grid_h, grid_w, 3), dtype=np.uint8)
    landcover_rgb[:, :, 0] = biome_grid
    landcover_rgb[:, :, 1] = feature_grid
    landcover_bytes = landcover_rgb.tobytes()

    elev_clamped = np.clip(elev_grid + 32768.0, 0, 65535.0 + 255.0 / 256.0)
    elev_int = elev_clamped.astype(np.uint32)
    r = np.clip(elev_int // 256, 0, 255).astype(np.uint8)
    rem = elev_int - r.astype(np.uint32) * 256
    g = np.clip(rem, 0, 255).astype(np.uint8)
    b = np.zeros((grid_h, grid_w), dtype=np.uint8)
    elevation_rgb = np.stack([r, g, b], axis=-1)
    elevation_bytes = elevation_rgb.tobytes()

    suffix = "_test" if test_mode else ""
    lc_path = os.path.join(OUTPUT_DIR, f"landcover{suffix}.png")
    el_path = os.path.join(OUTPUT_DIR, f"elevation{suffix}.png")
    with open(lc_path, "wb") as f:
        f.write(encode_png_rgb8(grid_w, grid_h, landcover_bytes))
    with open(el_path, "wb") as f:
        f.write(encode_png_rgb8(grid_w, grid_h, elevation_bytes))
    print(f"  wrote {lc_path} ({os.path.getsize(lc_path):,} bytes)")
    print(f"  wrote {el_path} ({os.path.getsize(el_path):,} bytes)")

    # Companion metadata for RealTerrainSampler.gd (values, not code --
    # the GDScript constants are still hand-kept in sync, documented
    # cross-reference, same convention as HexCoord.WORLD_UNITS_PER_REAL_METER).
    print("=== Summary ===")
    print(f"  WORLD_UNITS_PER_PIXEL = {WORLD_UNITS_PER_PIXEL}")
    print(f"  RASTER_ORIGIN_WORLD = ({min_x:.2f}, {min_y:.2f})")
    print(f"  raster size = ({grid_w}, {grid_h})")
    unique, counts = np.unique(biome_grid, return_counts=True)
    code_to_name = {v: k for k, v in _BIOME_CODE.items()}
    for code, count in zip(unique, counts):
        print(f"  biome {code_to_name.get(int(code), code)}: {count:,} px ({100*count/(grid_w*grid_h):.1f}%)")
    print(f"  elevation range: {elev_grid.min():.1f}m .. {elev_grid.max():.1f}m")
    print(f"  highland-overridden pixels: {int(override_mask.sum()):,}")
    print(f"  total time: {time.time() - t0:.1f}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", action="store_true", help="small validation window around Manchester")
    args = parser.parse_args()
    bake(test_mode=args.test)
