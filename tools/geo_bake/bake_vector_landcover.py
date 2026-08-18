"""Bakes real OSM land-cover vector data into a continuous triangle mesh.

Replaces the rasterize-then-sample path for CATEGORICAL land-cover data.
bake_landcover.py projects real OSM polygon rings onto a pixel grid, and
SubHexGroundView then draws one axis-aligned quad per sampled pixel -- so the
squares the user reported ("is not seamless at all, just has various
gradients of two biomes but they're still obviously squares") are a
rasterization artifact, not a rendering choice. No shader gradient can undo
it: the real boundary was already destroyed at bake time. The user's
direction was explicit that the fix must come from the source data, not from
hex geometry -- "no it shouldn't be based on the hex tile it should be based
on the real GB + Ireland open source data."

Elevation deliberately stays raster (bake_landcover.py keeps owning it). A
DEM is a continuous field sampled on a grid at source (Terrarium tiles are
raster), so rasterizing it loses nothing; only categorical boundaries suffer.
HIGHLAND/ESCARPMENT stay derived from that raster too -- neither is an OSM
class, they come from an elevation threshold over MOORLAND/FARMLAND/WOODLAND/
HEATHLAND (bake_landcover.py's own override pass), so they are applied on top
of this mesh's class rather than stored in it.

Pipeline, per chunk:

  1. Per class, union the RAW features that touch the chunk, THEN simplify the
     merged blob. Order matters: simplifying each feature first destroys
     anything near the tolerance -- measured, a 30m residential polygon
     simplified at a 30m tolerance vanished and the arrangement collapsed
     from ~89k vertices to 7,129.
  2. Snap to a fixed precision grid (shapely set_precision). Robustness, and
     it doubles as the wire format's quantization.
  3. Node the ENTIRE boundary network (class boundaries + chunk boundary +
     Voronoi size-cap cells) with one unary_union, then polygonize into
     faces. This is what makes the partition exact: GEOS overlay output is
     always noded, so adjacent faces share bit-identical vertices.
  4. Label each face by the highest-priority class containing its
     representative point.
  5. Constrained Delaunay per face (GEOS, via shapely). Adds no Steiner
     points, so shipped vertices == simplified boundary vertices.

Building the partition SEQUENTIALLY instead (each class differenced against
everything already claimed) was tried and measured first: 7 T-junctions on
the very first adjacent pair, because where a lower-priority class's boundary
meets the INTERIOR of a higher-priority class's edge, the higher-priority side
has no vertex there. Under Phase 4's vertex-displaced relief a hanging vertex
slides off its neighbour's straight edge and opens a visible crack. The
arrangement construction above measures 0 T-junctions.

Measured on the densest chunk in the corridor (Manchester city centre, 4096
world units square, 32,652 area features): 33,179 triangles, 20,389 unique
vertices, 306 KB, edge length median 24.0 / p95 93.6 / max 184.9 world units.
Extrapolated over the ~4,692 land hexes of MAP_BOUNDS at that (worst-case
urban) density: ~57 MB for all of GB + Ireland, against ~300 MB for
equivalent raster coverage and the 42 MB of fine rasters that today cover
only the corridor.

NOT DONE HERE, and deliberately not half-done: the coastline. This pass
covers inland land-cover over the baked corridor only, which is why OCEAN
never appears in PRIORITY below. BritishGeographyData._LAND_RLE is still a
whole-hex-quantized raster mask, and re-deriving the coast from the Natural
Earth GB+IRL vectors is its own sub-task -- it needs the land/ocean boundary
to become the mesh's outer boundary, which this chunk-rectangle domain does
not model yet.

DATA ATTRIBUTION: the land-cover geometry this script consumes is
OpenStreetMap data, ODbL licensed, which REQUIRES "(c) OpenStreetMap
contributors" to be shown in the shipped game. fetch_overpass.py flagged
this and deferred it; making OSM the primary source of rendered terrain
raises it from a nicety to a licensing obligation. Still not satisfied by
any in-game UI -- see todo.md.
"""

import argparse
import json
import math
import os
import sys
import time

import numpy as np
from shapely import constrained_delaunay_triangles, make_valid, set_precision, voronoi_polygons
from shapely.geometry import LineString, MultiPoint, Polygon, box
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

from bake_landcover import _BIOME_CODE, _LANDUSE_MAP, _NATURAL_MAP
from fetch_overpass import elements_to_features
from geo_projection import apply_affine, fit_affine, invert_affine, world_to_lonlat
from vector_mesh_format import ChunkTooLargeError, chunk_filename, decode_chunk, encode_chunk

# HexCoord.WORLD_UNITS_PER_REAL_METER (scripts/world/HexCoord.gd).
WU_PER_REAL_M = 0.1025599
# HexCoord.HEX_SIZE. One hex's area, used only to report KB/hex.
HEX_SIZE_WU = 512.0
HEX_AREA_WU = 3.0 * math.sqrt(3.0) / 2.0 * HEX_SIZE_WU ** 2

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data", "mesh")
OVERPASS_CACHE = os.path.join(os.path.dirname(__file__), "cache", "overpass")

## 4096 world units square (~24.6 hexes). Sized so the densest measured chunk
## stays inside the wire format's uint16 vertex index range: Manchester city
## centre came to 20,389 vertices, a ~3.2x margin under 65,536.
CHUNK_SIZE_WU = 4096.0

## Boundary simplification tolerance. The user asked for triangles "of
## differing sizes (mostly smaller but also up to same size as current
## tactical view biome tiles)"; one SubHexGroundView rendered cell is
## SUB_HEX_GRID_SPAN/_GRID_N = 1024/11 = 93.1 world units, so ~93 wu is the
## stated upper bound. Swept 60/150/300/600 real m against that: 300m lands
## p95 edge length at 93.6 wu -- at the bound, with 95% smaller. 60m gave
## 7,587 triangles/hex (31x today's 242) for detail far below the bound;
## 600m gave a p95 of 184.7 wu, double it.
SIMPLIFY_TOLERANCE_M = 300.0

## Precision grid, in world units. 1.0 wu = 9.8 real m -- finer than the 30m
## sub-cell that Phase 2's mechanical queries resolve against, so the stored
## boundary is never coarser than the question being asked of it. Also the
## wire format's quantization step.
QUANT_WU = 1.0

## Input FEATURE parts below this are dropped before they reach the boundary
## network -- 0.04 km2, a 200x200m patch, which at a 300m simplification
## tolerance is already near the noise floor.
##
## Applies to features only, never to arrangement faces. Filtering faces was
## measured at 96.80% area coverage (93.83% in the densest chunk): a face is a
## region of space, so dropping one punches a hole in the partition rather
## than merging it into a neighbour. Faces are cheap to keep -- their vertices
## are already in the network whether or not the face is triangulated.
MIN_PART_AREA_M2 = 40000.0

## Irregular triangle size cap. Without it the empty-moorland background is a
## single face spanning the chunk and CDT gives it a 4096-wu edge; a triangle
## ~40 km across cannot follow terrain, so Phase 4's vertex-displaced relief
## would interpolate elevation linearly across it. A SQUARE subdivision grid
## would reintroduce exactly the artifact this epic exists to remove, so the
## cap is a Voronoi diagram of jittered seeds -- irregular convex cells, no
## axis-aligned edges. Measured cost: +31% triangles (25,301 -> 33,179),
## max edge 4096 -> 184.9.
VORONOI_SPACING_WU = 120.0
VORONOI_JITTER_WU = 30.0

## Highest priority first. Resolves what a raster bake left to chance:
## bake_landcover.rasterize_features_onto_grid()'s own doc comment records
## that area features used to overwrite each other "in whatever order
## Overpass happened to return them in (effectively random per bake run)".
##
## WATERWAY ranks above the built environment here, which is the OPPOSITE of
## the raster bake's rule that a waterway "NEVER overwrites any real polygon-
## derived classification, full stop". That reversal is resolution-bound, not
## a disagreement: that rule exists because at 878m/pixel a river's
## rasterization buffer was a ~527m smear that measurably tripled water
## around Manchester (22.9% -> 28.9% of nearby pixels). This bake carries a
## river as real geometry at its own width, so "a river genuinely running
## through a city centre should read as a visible ribbon of water through the
## urban texture" -- the thing that comment records wanting and could not
## have at raster resolution -- is now just true.
##
## No OCEAN: this pass is inland-only, see the module doc comment.
PRIORITY = ["WATERWAY", "INDUSTRIAL", "URBAN", "WETLAND", "WOODLAND", "HEATHLAND", "FARMLAND"]

## Every face the arrangement produces that no PRIORITY class contains. Matches
## bake_landcover.py's own convention, where biome code 0 doubles as "no real
## polygon ever touched this pixel".
DEFAULT_CLASS = "MOORLAND"


def _discard_stale(out_dir: str, chunk_x: int, chunk_y: int) -> None:
    """Remove a chunk that this run did not produce.

    A chunk that fails or yields nothing used to leave the PREVIOUS run's file
    in place, so the output directory silently mixed generations: after the
    tile cache was repaired, 7 chunks threw and the engine went on loading
    their pre-repair versions -- 5 files on disk that no run had written,
    including two of Manchester's, and nothing said so. The verifier counted
    110 chunks against the bake's own reported 105, which is the only reason
    it was noticed.
    """
    path = os.path.join(out_dir, chunk_filename(chunk_x, chunk_y))
    if os.path.exists(path):
        os.remove(path)
        print(f"    removed stale {os.path.basename(path)} (this run produced nothing for it)",
              flush=True)


def _snap(geometry):
    """set_precision onto the QUANT_WU grid, repairing the input first.

    Returns None if the geometry cannot be snapped at all, so a caller can
    drop one class rather than lose the whole chunk.
    """
    try:
        return set_precision(geometry, QUANT_WU)
    except Exception:  # noqa: BLE001 -- GEOSException is not importable by name here
        pass
    try:
        return set_precision(make_valid(geometry), QUANT_WU)
    except Exception:  # noqa: BLE001
        return None


def _tile_bbox_from_name(name: str) -> tuple[float, float, float, float]:
    """(min_lat, min_lon, max_lat, max_lon) from fetch_overpass's cache
    filename convention."""
    min_lat, min_lon, max_lat, max_lon = (float(p) for p in name[:-len(".json")].split("_"))
    return min_lat, min_lon, max_lat, max_lon


class _TileGeometryCache:
    """Parses one cached Overpass tile into projected shapely geometry, keeping
    the few most recently used tiles.

    A chunk is 4096 world units and a 0.5-degree tile is ~5,640 (0.5 deg lat
    ~= 55 km, times WU_PER_REAL_M), so a chunk straddles 1-4 tiles and
    row-major chunk iteration revisits the same tiles many times. Parsing the
    largest cached tile costs ~1s of JSON plus ~3.5s of projection and
    polygon construction, so rebuilding per chunk would dominate the bake.

    Bounded to `capacity` tiles because the geometry is not small -- a dense
    tile holds ~45,000 shapely polygons. Capacity must stay above the most
    tiles a single chunk can overlap (measured: 5 around Manchester, where
    the corridor bake used overlapping 0.3-degree and 0.5-degree tilings), or
    a chunk evicts tiles it is still using and reparses them.
    """

    def __init__(self, capacity: int = 8):
        self.capacity = capacity
        self._entries: dict[str, dict] = {}
        self._order: list[str] = []
        self.parses = 0

    def get(self, name: str, transform) -> dict:
        if name in self._entries:
            self._order.remove(name)
            self._order.append(name)
            return self._entries[name]

        path = os.path.join(OVERPASS_CACHE, name)
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        entry = _build_tile_geometry(elements_to_features(raw), transform)
        self.parses += 1

        self._entries[name] = entry
        self._order.append(name)
        while len(self._order) > self.capacity:
            self._entries.pop(self._order.pop(0), None)
        return entry


def _build_tile_geometry(features: list[dict], transform) -> dict:
    """Classify, project to world space, and build shapely geometry for one
    tile's features.

    Waterway LINES are buffered to a real-world width here rather than being
    left as lines. bake_landcover.py derives its buffer from pixel size and
    says so explicitly -- "the buffer's job is rasterization correctness, not
    modelling true real-world width" -- which is exactly the approximation
    this bake exists to drop.

    The width is floored at 1.5 sub-cells because WATERWAY is
    impassable-without-a-Bridge (HexPathfinder.is_water_crossing_blocked()).
    A ribbon narrower than one 30m sub-cell could fall between sampled cells
    and leave gaps in that barrier, silently reopening exactly the crossings
    the rule exists to close.
    """
    SUB_CELL_M = 30.0  # HexCoord.SUB_HEX_CELL_SIZE_METERS
    TYPICAL_RIVER_WIDTH_M = 40.0
    half_width = max(TYPICAL_RIVER_WIDTH_M, SUB_CELL_M * 1.5) * 0.5 * WU_PER_REAL_M

    by_class: dict[str, list] = {}
    skipped = 0
    for feat in features:
        tags = feat["tags"]
        waterway = tags.get("waterway")
        if waterway:
            cls, is_line = "WATERWAY", True
        else:
            cls = _LANDUSE_MAP.get(tags.get("landuse")) or _NATURAL_MAP.get(tags.get("natural"))
            is_line = False
            if not cls:
                continue
        ring = feat["ring"]
        if len(ring) < (2 if is_line else 4):
            skipped += 1
            continue
        world = [apply_affine(transform, lon, lat) for lon, lat in ring]
        try:
            if is_line:
                geom = LineString(world).buffer(half_width, resolution=2)
            else:
                geom = Polygon(world)
                if not geom.is_valid:
                    geom = geom.buffer(0)  # self-intersecting OSM ring -> valid polygon
            if geom.is_empty or not geom.is_valid:
                skipped += 1
                continue
        except Exception:  # noqa: BLE001 -- a single malformed ring must not kill the bake
            skipped += 1
            continue
        by_class.setdefault(cls, []).append(geom)

    trees = {cls: STRtree(geoms) for cls, geoms in by_class.items()}
    return {"by_class": by_class, "trees": trees, "skipped": skipped}


def _voronoi_cut_lines(chunk: Polygon) -> LineString | None:
    """Irregular size-cap cell boundaries covering `chunk`.

    Seeded from the chunk's own integer origin so a re-bake is byte-identical
    -- the jitter must not vary run to run or every chunk's vertex data
    changes on every bake.
    """
    minx, miny, maxx, maxy = chunk.bounds
    rng = np.random.default_rng((abs(int(minx)) * 73856093) ^ (abs(int(miny)) * 19349663))
    seeds = []
    y = miny - VORONOI_SPACING_WU
    while y <= maxy + VORONOI_SPACING_WU:
        x = minx - VORONOI_SPACING_WU
        while x <= maxx + VORONOI_SPACING_WU:
            seeds.append((x + rng.uniform(-VORONOI_JITTER_WU, VORONOI_JITTER_WU),
                          y + rng.uniform(-VORONOI_JITTER_WU, VORONOI_JITTER_WU)))
            x += VORONOI_SPACING_WU
        y += VORONOI_SPACING_WU
    if len(seeds) < 3:
        return None
    cells = voronoi_polygons(MultiPoint(seeds), extend_to=chunk)
    cut = unary_union([c.boundary for c in cells.geoms]).intersection(chunk)
    if cut.is_empty:
        return None
    return set_precision(cut, QUANT_WU)


def _parts(geom) -> list[Polygon]:
    if geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    return [p for p in geom.geoms if isinstance(p, Polygon) and not p.is_empty]


def build_chunk_mesh(chunk_x: int, chunk_y: int, transform, tile_cache: _TileGeometryCache,
                     tile_names: list[str]) -> dict | None:
    """Arrangement -> labelled faces -> CDT for one chunk. None if the chunk
    produced no geometry at all."""
    origin_x = chunk_x * CHUNK_SIZE_WU
    origin_y = chunk_y * CHUNK_SIZE_WU
    chunk = set_precision(box(origin_x, origin_y,
                              origin_x + CHUNK_SIZE_WU, origin_y + CHUNK_SIZE_WU), QUANT_WU)

    tol = SIMPLIFY_TOLERANCE_M * WU_PER_REAL_M
    min_area = MIN_PART_AREA_M2 * WU_PER_REAL_M * WU_PER_REAL_M

    # Which cached Overpass tiles overlap this chunk, in lon/lat.
    inv_linear, offset = invert_affine(transform)
    corners = [(origin_x, origin_y), (origin_x + CHUNK_SIZE_WU, origin_y),
               (origin_x, origin_y + CHUNK_SIZE_WU),
               (origin_x + CHUNK_SIZE_WU, origin_y + CHUNK_SIZE_WU)]
    lonlats = [world_to_lonlat(inv_linear, offset, x, y) for x, y in corners]
    c_min_lon = min(p[0] for p in lonlats)
    c_max_lon = max(p[0] for p in lonlats)
    c_min_lat = min(p[1] for p in lonlats)
    c_max_lat = max(p[1] for p in lonlats)

    relevant = []
    for name in tile_names:
        t_min_lat, t_min_lon, t_max_lat, t_max_lon = _tile_bbox_from_name(name)
        if t_max_lon < c_min_lon or t_min_lon > c_max_lon:
            continue
        if t_max_lat < c_min_lat or t_min_lat > c_max_lat:
            continue
        relevant.append(name)
    if not relevant:
        return None

    # Step 1+2: per class, union the raw features touching this chunk, then
    # simplify and snap the merged blob. See the module doc comment for why
    # this order and not the reverse.
    # One pass over the relevant tiles collecting candidates for EVERY class,
    # not one pass per class. A chunk straddles up to ~5 cached tiles, so
    # fetching inside the class loop re-parsed all of them once per class:
    # measured 19.7s of tile parsing charged 7 times over, 136s of a 156s
    # chunk, entirely cache thrashing.
    candidates_by_class: dict[str, list] = {}
    for name in relevant:
        entry = tile_cache.get(name, transform)
        for cls in PRIORITY:
            tree = entry["trees"].get(cls)
            if tree is None:
                continue
            hits = candidates_by_class.setdefault(cls, [])
            for i in tree.query(chunk):
                g = tree.geometries[i]
                if g.intersects(chunk):
                    hits.append(g)

    merged: dict[str, object] = {}
    n_features = 0
    for cls in PRIORITY:
        candidates = candidates_by_class.get(cls)
        if not candidates:
            continue
        n_features += len(candidates)
        g = unary_union(candidates).intersection(chunk)
        if g.is_empty:
            continue
        # make_valid() between simplify and set_precision, not after.
        # preserve_topology=True keeps a ring from crossing ITSELF but does not
        # guarantee a valid polygon once thousands of unioned OSM features are
        # involved, and set_precision on an invalid input throws
        # "TopologyException: side location conflict" rather than returning
        # anything -- which failed 7 chunks outright, including two of
        # Manchester's, the first time the healed tile cache made them dense
        # enough to hit it.
        g = _snap(g.simplify(tol, preserve_topology=True))
        if g is None or g.is_empty or not g.is_valid:
            continue
        keep = [p for p in _parts(g) if p.area >= min_area]
        if not keep:
            continue
        g = unary_union(keep).intersection(chunk)
        if not g.is_empty:
            merged[cls] = g

    # Step 3: one noded line network -> faces.
    lines = [chunk.boundary]
    cut = _voronoi_cut_lines(chunk)
    if cut is not None:
        lines.append(cut)
    for g in merged.values():
        b = g.boundary
        if b is not None and not b.is_empty:
            lines.append(b)
    # Every face is kept -- see MIN_PART_AREA_M2. The partition must tile the
    # chunk exactly; a dropped face is a hole, and the holes are worst exactly
    # where the arrangement is densest.
    faces = list(polygonize(unary_union(lines)))
    if not faces:
        return None

    # Step 4: label each face by highest-priority containing class.
    trees = {cls: STRtree(_parts(g)) for cls, g in merged.items()}
    labelled = []
    for f in faces:
        pt = f.representative_point()  # guaranteed inside f, unlike a centroid on a concave face
        label = DEFAULT_CLASS
        for cls in PRIORITY:
            tree = trees.get(cls)
            if tree is None:
                continue
            hits = tree.query(pt)
            if len(hits) and any(tree.geometries[i].contains(pt) for i in hits):
                label = cls
                break
        labelled.append((f, label))

    # Step 5: CDT each face, welding vertices into one indexed mesh.
    vert_index: dict[tuple[int, int], int] = {}
    verts: list[tuple[int, int]] = []
    tris: list[tuple[int, int, int]] = []
    tri_classes: list[int] = []
    for face, label in labelled:
        code = _BIOME_CODE[label]
        result = constrained_delaunay_triangles(face)
        for tri in (result.geoms if hasattr(result, "geoms") else [result]):
            idx = []
            for x, y in tri.exterior.coords[:3]:
                q = (int(round((x - origin_x) / QUANT_WU)), int(round((y - origin_y) / QUANT_WU)))
                got = vert_index.get(q)
                if got is None:
                    got = len(verts)
                    vert_index[q] = got
                    verts.append(q)
                idx.append(got)
            # Reject on the QUANTIZED cross product, not just on duplicate
            # indices. Three points can stay distinct as integers yet snap
            # into collinearity on the grid: the in-engine verifier measured
            # 273 zero-area triangles across 442,658 (0.06%), every one with
            # a 1.0-wu edge, when only duplicate indices were checked. A
            # zero-area triangle draws nothing and yields a degenerate normal
            # once Phase 4 displaces vertices for relief.
            ax, ay = verts[idx[0]]
            bx, by = verts[idx[1]]
            cx_, cy_ = verts[idx[2]]
            if (bx - ax) * (cy_ - ay) - (by - ay) * (cx_ - ax) == 0:
                continue
            tris.append((idx[0], idx[1], idx[2]))
            tri_classes.append(code)

    if not tris:
        return None
    return {
        "origin": (origin_x, origin_y), "verts": verts, "tris": tris,
        "tri_classes": tri_classes, "faces": len(faces), "features": n_features,
    }


def bake(q_range: tuple[int, int], r_range: tuple[int, int], limit: int | None = None,
         out_dir: str = OUTPUT_DIR) -> None:
    print("=== Step 1: fit lon/lat -> world affine ===")
    transform = fit_affine()

    tile_names = sorted(n for n in os.listdir(OVERPASS_CACHE) if n.endswith(".json"))
    # A tile the server genuinely has nothing for comes back as a ~258-byte
    # response whose elements list is empty; keeping it in the list only costs
    # a pointless parse. A tile that FAILED is no longer written at all
    # (fetch_overpass.fetch_tile), so it is absent here rather than
    # indistinguishable from an empty one -- which is what let 22 poisoned
    # tiles bake into flat rectangles before that was fixed.
    tile_names = [n for n in tile_names
                  if os.path.getsize(os.path.join(OVERPASS_CACHE, n)) > 64]
    print(f"\n=== Step 2: {len(tile_names)} non-empty cached Overpass tiles ===")

    # World-space extent of the requested axial range, then the chunk grid over it.
    from geo_projection import axial_to_world
    xs, ys = [], []
    for q in q_range:
        for r in r_range:
            x, y = axial_to_world(q, r)
            xs.append(x)
            ys.append(y)
    min_cx = int(math.floor(min(xs) / CHUNK_SIZE_WU))
    max_cx = int(math.floor(max(xs) / CHUNK_SIZE_WU))
    min_cy = int(math.floor(min(ys) / CHUNK_SIZE_WU))
    max_cy = int(math.floor(max(ys) / CHUNK_SIZE_WU))
    all_chunks = [(cx, cy) for cy in range(min_cy, max_cy + 1) for cx in range(min_cx, max_cx + 1)]
    if limit is not None:
        all_chunks = all_chunks[:limit]
    print(f"q={q_range} r={r_range} -> chunk grid x {min_cx}..{max_cx}, y {min_cy}..{max_cy} "
          f"({len(all_chunks)} chunks of {CHUNK_SIZE_WU:.0f} wu)")

    os.makedirs(out_dir, exist_ok=True)
    cache = _TileGeometryCache()

    print(f"\n=== Step 3: bake {len(all_chunks)} chunks ===")
    written = skipped = 0
    total_bytes = total_tris = total_verts = 0
    max_verts_seen = 0
    started = time.time()
    for n, (cx, cy) in enumerate(all_chunks, start=1):
        t0 = time.time()
        try:
            mesh = build_chunk_mesh(cx, cy, transform, cache, tile_names)
        except Exception as exc:  # noqa: BLE001
            print(f"  [{n}/{len(all_chunks)}] chunk {cx},{cy} FAILED: {type(exc).__name__}: {exc}",
                  flush=True)
            _discard_stale(out_dir, cx, cy)
            skipped += 1
            continue
        if mesh is None:
            _discard_stale(out_dir, cx, cy)
            skipped += 1
            continue

        ox, oy = mesh["origin"]
        try:
            blob = encode_chunk(ox, oy, QUANT_WU, mesh["verts"], mesh["tris"], mesh["tri_classes"])
        except ChunkTooLargeError as exc:
            # Refuse rather than wrap -- a wrapped index decodes as geometry
            # folded back on itself. CHUNK_SIZE_WU is the lever.
            print(f"  [{n}/{len(all_chunks)}] chunk {cx},{cy} EXCEEDS FORMAT LIMIT: {exc}", flush=True)
            skipped += 1
            continue

        # Round-trip every chunk. A format bug caught here is one that would
        # otherwise surface in-engine as unexplained geometry.
        back = decode_chunk(blob)
        assert back["verts"] == mesh["verts"], f"chunk {cx},{cy} vertex round-trip mismatch"
        assert back["tris"] == mesh["tris"], f"chunk {cx},{cy} triangle round-trip mismatch"
        assert back["tri_classes"] == mesh["tri_classes"], f"chunk {cx},{cy} class round-trip mismatch"

        with open(os.path.join(out_dir, chunk_filename(cx, cy)), "wb") as f:
            f.write(blob)

        written += 1
        total_bytes += len(blob)
        total_tris += len(mesh["tris"])
        total_verts += len(mesh["verts"])
        max_verts_seen = max(max_verts_seen, len(mesh["verts"]))
        hexes = CHUNK_SIZE_WU * CHUNK_SIZE_WU / HEX_AREA_WU
        print(f"  [{n}/{len(all_chunks)}] chunk {cx},{cy}: {mesh['features']} feats, "
              f"{mesh['faces']} faces, {len(mesh['tris'])} tris, {len(mesh['verts'])} verts, "
              f"{len(blob)/1024:.0f} KB ({len(blob)/1024/hexes:.1f} KB/hex) in {time.time()-t0:.1f}s",
              flush=True)

    elapsed = time.time() - started
    print(f"\n=== Done in {elapsed/60:.1f} min ===")
    print(f"  {written} chunks written, {skipped} skipped (no geometry / failed)")
    print(f"  tile parses: {cache.parses} (cache capacity {cache.capacity})")
    if written:
        hexes = written * CHUNK_SIZE_WU * CHUNK_SIZE_WU / HEX_AREA_WU
        print(f"  {total_tris} triangles, {total_verts} vertices, {total_bytes/1024/1024:.1f} MB")
        print(f"  {total_bytes/1024/hexes:.1f} KB/hex, {total_tris/hexes:.0f} tris/hex "
              f"(SubHexGroundView draws 242 tris/hex today)")
        print(f"  worst chunk: {max_verts_seen} verts (uint16 index limit is 65536)")
        print(f"  extrapolated to the ~4,692 land hexes of MAP_BOUNDS: "
              f"{total_bytes/1024/hexes*4692/1024:.0f} MB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--q", type=int, nargs=2, default=[55, 105],
                    help="axial q range to cover (default: bake_landcover.CORRIDOR_Q)")
    ap.add_argument("--r", type=int, nargs=2, default=[85, 160],
                    help="axial r range to cover (default: bake_landcover.CORRIDOR_R)")
    ap.add_argument("--limit", type=int, default=None,
                    help="bake at most N chunks -- for validating the pipeline before a long run")
    ap.add_argument("--out", default=OUTPUT_DIR)
    args = ap.parse_args()
    bake(tuple(args.q), tuple(args.r), limit=args.limit, out_dir=args.out)
