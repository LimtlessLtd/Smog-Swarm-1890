"""Bakes real OSM land-cover vector data into a continuous triangle mesh.

Replaces the rasterize-then-sample path for CATEGORICAL land-cover data.
bake_landcover.py projects real OSM polygon rings onto a pixel grid, and the
old per-hex ground then drew one axis-aligned quad per sampled pixel -- so the
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

Coastline (2026-08-20): the arrangement domain for each chunk is no longer
the plain CHUNK_SIZE_WU rectangle, it is (rectangle ∩ real coastline) --
coastline.land_polygon_world(), Natural Earth's GBR+IRL landmass projected
through the same affine every other class here already uses. OCEAN still
never appears in PRIORITY: sea is simply ground no chunk's arrangement
covers, the same "write nothing, let SeaView show through" contract a
zero-feature chunk already used. BritishGeographyData._LAND_RLE stays
whole-hex-quantized and is untouched -- it is the game's MECHANICAL
land/ocean truth (HexMapGenerator, pathfinding, fog), a separate system this
pass does not touch; see todo.md's "1b" entry for the measured disagreement
between the two.

DATA ATTRIBUTION: the land-cover geometry this script consumes is
OpenStreetMap data, ODbL licensed, which REQUIRES "(c) OpenStreetMap
contributors" to be shown in the shipped game. fetch_overpass.py flagged
this and deferred it; making OSM the primary source of rendered terrain
raises it from a nicety to a licensing obligation. Still not satisfied by
any in-game UI -- see todo.md.
"""

import argparse
import io
import json
import math
import os
import re
import sys
import time

import numpy as np
from shapely import constrained_delaunay_triangles, make_valid, set_precision, voronoi_polygons
from shapely.geometry import LineString, MultiPoint, Polygon, box
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

from bake_landcover import _BIOME_CODE, _LANDUSE_MAP, _NATURAL_MAP
from coastline import land_polygon_world
from fetch_overpass import elements_to_features
from geo_projection import apply_affine, fit_affine, invert_affine, world_to_lonlat
from vector_mesh_format import ChunkTooLargeError, chunk_filename, decode_chunk, encode_chunk

# HexCoord.WORLD_UNITS_PER_REAL_METER (scripts/world/HexCoord.gd).
WU_PER_REAL_M = 0.1025599
# HexCoord.HEX_SIZE. One hex's area, used only to report KB/hex.
HEX_SIZE_WU = 512.0
HEX_AREA_WU = 3.0 * math.sqrt(3.0) / 2.0 * HEX_SIZE_WU ** 2

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "terrain_data", "mesh")
## Default tile cache. fetch_overpass.py writes here; extract_pbf.py writes an
## equivalent set covering all of GB+Ireland to cache/tiles_pbf, and --cache
## selects between them. Both hold the same Overpass-shaped JSON under the same
## <minlat>_<minlon>_<maxlat>_<maxlon> filenames, so nothing below this line
## knows or cares which source produced a tile.
OVERPASS_CACHE = os.path.join(os.path.dirname(__file__), "cache", "overpass")
PBF_CACHE = os.path.join(os.path.dirname(__file__), "cache", "tiles_pbf")


## BritishGeographyData.gd, parsed rather than duplicated. That file's
## _LAND_RLE is the game's own land/ocean truth (HexMapGenerator builds every
## OCEAN hex from it), so restating it here as a Python literal would create a
## second source that silently drifts the first time the coastline is re-baked.
LAND_RLE_GD = os.path.join(os.path.dirname(__file__), "..", "..",
                           "scripts", "world", "data", "BritishGeographyData.gd")


def land_chunks() -> set:
    """Chunk addresses containing any part of a LAND hex.

    Chunks with none are pure open sea. Baking them is worse than useless: with
    no land-cover features to label faces, every face falls to DEFAULT_CLASS and
    a 40km square of the North Sea renders as solid moorland on top of SeaView's
    blue. Measured on a full-map run before this filter existed: 21 of the first
    126 chunks written were pure sea. It also cuts the grid from 1,802 chunks to
    272, since most of a UK+Ireland bounding box is water.

    A hex's own EXTENT is used, not just its centre -- a coastal hex centred in
    one chunk still covers ground in the next, and missing that would carve
    straight-edged bites out of the coast.
    """
    text = io.open(LAND_RLE_GD, encoding="utf-8").read()
    body = text.split("const _LAND_RLE: Array = [", 1)[1]
    half_w = HEX_SIZE_WU * math.sqrt(3.0) / 2.0
    half_h = HEX_SIZE_WU
    chunks = set()
    for line in body.splitlines():
        if line.strip() == "]":
            break
        row = re.match(r"\s*\[(-?\d+),\s*\[(.*)\]\],?\s*", line)
        if not row:
            continue
        r = int(row.group(1))
        for lo, hi in re.findall(r"Vector2i\((-?\d+),\s*(-?\d+)\)", row.group(2)):
            for q in range(int(lo), int(hi) + 1):
                x, y = axial_to_world_py(q, r)
                for cx in range(int(math.floor((x - half_w) / CHUNK_SIZE_WU)),
                                int(math.floor((x + half_w) / CHUNK_SIZE_WU)) + 1):
                    for cy in range(int(math.floor((y - half_h) / CHUNK_SIZE_WU)),
                                    int(math.floor((y + half_h) / CHUNK_SIZE_WU)) + 1):
                        chunks.add((cx, cy))
    if not chunks:
        raise SystemExit(f"parsed no land hexes from {LAND_RLE_GD} -- has its format changed?")
    return chunks


def axial_to_world_py(q: int, r: int) -> tuple:
    """HexCoord.axial_to_world. Duplicated from geo_projection.axial_to_world
    only to avoid an import cycle at module scope."""
    return (HEX_SIZE_WU * (math.sqrt(3.0) * q + math.sqrt(3.0) / 2.0 * r),
            HEX_SIZE_WU * 1.5 * r)


## 4096 world units square (~24.6 hexes). Sized so the densest measured chunk
## stays inside the wire format's uint16 vertex index range: Manchester city
## centre came to 20,389 vertices, a ~3.2x margin under 65,536.
CHUNK_SIZE_WU = 4096.0

## Boundary simplification tolerance. The user asked for triangles "of
## differing sizes (mostly smaller but also up to same size as current
## tactical view biome tiles)"; one of those square rendered cells was
## SUB_HEX_GRID_SPAN/11 = 1024/11 = 93.1 world units, so ~93 wu is the
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

## --- Waterway ribbon geometry -------------------------------------------
## A waterway arrives as a LINE and is buffered into a ribbon. Both numbers
## below are in real metres; the ribbon is 45m wide, i.e. 4.62 wu.
##
## The width floor is 1.5 sub-cells because WATERWAY is impassable-without-a-
## Bridge (HexPathfinder.is_water_crossing_blocked()): a ribbon narrower than
## one 30m sub-cell can fall between sampled cells and silently reopen the
## crossings that rule exists to close.
SUB_CELL_M = 30.0  # HexCoord.SUB_HEX_CELL_SIZE_METERS
TYPICAL_RIVER_WIDTH_M = 40.0
WATERWAY_HALF_WIDTH_WU = max(TYPICAL_RIVER_WIDTH_M, SUB_CELL_M * 1.5) * 0.5 * WU_PER_REAL_M

## Simplification happens on the CENTRELINE, before buffering, and the merged
## ribbon is then simplified only a little (a fraction of its own half-width).
##
## Simplifying the buffered ribbon at SIMPLIFY_TOLERANCE_M instead -- which is
## what every other class gets, and what this used to do -- moves vertices by
## up to 30.8 wu across a shape only 4.62 wu wide, i.e. 6.7x its own width.
## Measured on one Manchester tile: river area went 58,558 -> 120,729 wu2
## (+106%) and mean width 4.52 -> 9.33 wu, so rivers drew at roughly double
## their true width with the width wandering along their length. Worse, it
## pinched as much as it bulged -- eroding the result by 1.0 wu broke it into
## 36 pieces where the same erosion leaves the centreline-simplified version
## in 10. Those pinch points are narrower than the 30m sub-cell the width
## floor above exists to guarantee, so this was a hole in the water barrier
## and not only an ugly river.
##
## Chaikin smoothing runs after the simplify: Douglas-Peucker leaves an
## angular polyline, and a river that turns in hard corners reads as wrong
## even at the correct width. One iteration is enough to round the corners
## without chasing the noise the simplify just removed.
WATERWAY_LINE_TOLERANCE_M = 60.0
WATERWAY_SMOOTH_ITERATIONS = 1
WATERWAY_BUFFER_RESOLUTION = 8  ## Segments per quarter-circle on bends/caps. Was 2, which is visibly faceted at this width.
WATERWAY_SIMPLIFY_FRACTION = 0.25  ## Of WATERWAY_HALF_WIDTH_WU.

## --- Boundary conditioning ----------------------------------------------
## Run on each class's merged blob BEFORE it is simplified. Added 2026-08-19
## against a user report that biomes "have such jagged angles and tiny slivers
## of land"; preview_chunk_mesh.py renders the before/after.
##
## The jaggedness was not noisy source data, it was SIMPLIFY_TOLERANCE_M
## being larger than the features it was applied to. British farmland and
## woodland arrive from OSM as thousands of individual field/copse polygons
## roughly 100-300m across, i.e. AT or BELOW the 300m tolerance. Douglas-
## Peucker with preserve_topology=True refuses to delete a ring outright, so
## instead of vanishing each one collapses to the 3-4 extreme points that a
## ring cannot go below -- a spike. That is the shard texture covering the
## rendered chunk: one triangular splinter per real field.
##
## Simply lowering the tolerance keeps the shapes but multiplies vertex count
## across the whole map. Welding first is better on both counts: a closing
## merges the field mosaic into contiguous regions, after which the tolerance
## applies to a REGION's outer boundary -- which is what a 300m tolerance is
## the right size for -- and the interior boundaries it used to shred are
## gone rather than simplified.
##
## Distances are in real metres. QUANT_WU is 1.0 wu = 9.75m, so anything
## below ~20m is below the precision grid and does nothing.
##
## WATERWAY is exempt from all three: its centreline is already simplified and
## Chaikin-smoothed before buffering, and the ribbon is only 4.62 wu wide, so
## an erosion of any useful size would break it into pieces -- the same
## failure WATERWAY_LINE_TOLERANCE_M records, and a hole in the
## Bridge-mandatory water barrier rather than only an ugly river.

## Closing (dilate then erode): welds neighbouring same-class features across
## the lanes, hedge lines and hairline slivers of no-data that separate them
## in OSM, and fills interior pinholes. Bridges gaps up to 2x this wide.
FIELD_WELD_M = 90.0

## Opening (erode then dilate): erases what the weld could not join -- thin
## tendrils, one-field spurs hanging off a region, and slivers narrower than
## 2x this. At 5km per macro hex an 80m-wide strip of anything is under 2% of
## one hex and cannot read as its own biome on screen.
SLIVER_OPEN_M = 40.0

## Classes welded and opened at a fraction of those distances.
##
## A weld can only claim ground no HIGHER-priority class covers, because
## faces are still labelled by PRIORITY afterwards. FARMLAND is last, so a
## generous weld on it takes nothing but DEFAULT_CLASS -- ground no real
## polygon ever described -- which is the correct owner for the lane between
## two fields anyway. A weld on a class near the TOP of the list takes ground
## from the real classes below it: measured on chunk 29,15, welding WOODLAND
## at 100m grew it from 6.81% of the chunk to 10.83%, all of it out of
## farmland, because a 150m gap between two copses is usually a field and not
## more wood. So the discrete vegetation classes are welded only far enough to
## close hairline no-data slits, and the built classes likewise.
##
## The opening is reduced with it because these are the classes whose real
## features are smallest: at the full 40m a copse under 80m across is erased,
## and chunk 29,15 lost woodland outright (6.81% -> 5.95%).
CONSERVATIVE_CLASSES = {"WOODLAND", "HEATHLAND", "WETLAND", "URBAN", "INDUSTRIAL"}
CONSERVATIVE_FRACTION = 0.45

## Segments per quarter circle in those buffers. Low on purpose: the simplify
## immediately after discards the detail, so a higher value only costs time.
CONDITION_BUFFER_RESOLUTION = 4

## Chaikin corner-cutting on the simplified rings, cyclic (no pinned
## endpoints, unlike the open centreline in _chaikin). Douglas-Peucker output
## is an angular polyline and a biome boundary that turns in hard corners
## reads as wrong even when it is in the right place -- the same reason
## WATERWAY_SMOOTH_ITERATIONS exists. Each iteration doubles ring vertices.
SMOOTH_ITERATIONS = 1

## Smoothing applies to EVERY class except WATERWAY. URBAN and INDUSTRIAL were
## exempted at first, on the argument that a city block and a mill yard are
## built straight and rounding them trades one wrong shape for another. The
## render disproved it: the straight edges the exemption preserved are not the
## real ones. A village's footprint is a small polygon, so the 300m simplify
## turns it into the same spike it turns a field into, and the exemption only
## kept those spikes sharp. Smoothed, chunk 30,22's villages read as
## settlements and URBAN's share moves 8.32% -> 7.98% -- it costs almost no
## area, because rounding a corner takes only the corner.
##
## At 5km per macro hex nothing resolves an individual block anyway, so there
## was no real straightness being defended.

## An isolated pocket of UNCLAIMED ground smaller than this is given to
## whichever class it shares the most boundary with. 0.25 km2, a ~500m patch,
## a tenth of a macro hex across.
##
## DEFAULT_CLASS is not a survey result, it is "no OSM polygon covers this" --
## so a 300m pocket of it enclosed by a city is not moorland in London, it is a
## street junction nobody drew a landuse polygon over. The conditioning above
## cannot reach these because they are not part of any class's geometry: they
## are what is LEFT once every class has been welded, and on chunk 33,27
## (London) they were the grey city's remaining olive confetti.
##
## Only ever absorbs unclaimed ground, so it cannot take area from a real
## class. Real moorland is safe for the opposite reason: on an actual moor the
## unclaimed region is one connected part covering most of the chunk (measured
## 89% on chunk 25,9), which is far above this threshold and stays as it is.
DEFAULT_ABSORB_AREA_M2 = 250000.0

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

    def __init__(self, cache_dir: str, capacity: int = 16):
        self.cache_dir = cache_dir
        self.capacity = capacity
        self._entries: dict[str, dict] = {}
        self._order: list[str] = []
        self.parses = 0

    def get(self, name: str, transform) -> dict:
        if name in self._entries:
            self._order.remove(name)
            self._order.append(name)
            return self._entries[name]

        path = os.path.join(self.cache_dir, name)
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        entry = _build_tile_geometry(elements_to_features(raw), transform)
        self.parses += 1

        self._entries[name] = entry
        self._order.append(name)
        while len(self._order) > self.capacity:
            self._entries.pop(self._order.pop(0), None)
        return entry


def _chaikin(coords, iterations: int):
    """Corner-cutting subdivision: replace each vertex with two points at 1/4
    and 3/4 along its adjacent segments, keeping the endpoints pinned.

    Chosen over a spline because it cannot overshoot -- every output point is a
    convex combination of two input points, so a smoothed centreline stays
    inside the polyline's own hull and can never wander off the real river.
    Each iteration roughly doubles the vertex count, which is why
    WATERWAY_SMOOTH_ITERATIONS is 1.
    """
    points = list(coords)
    for _ in range(iterations):
        smoothed = [points[0]]
        for a, b in zip(points, points[1:]):
            smoothed.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            smoothed.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        smoothed.append(points[-1])
        points = smoothed
    return points


def _waterway_ribbon(line: LineString, half_width: float):
    """Centreline -> simplify -> smooth -> buffer, in that order. See
    WATERWAY_LINE_TOLERANCE_M for why the order is the whole point.

    preserve_topology=False on the line simplify: a LINE cannot collapse to
    nothing the way a thin polygon can (its endpoints are pinned), so the
    guard that protects small polygons buys nothing here and only keeps
    vertices the buffer would then have to round off.
    """
    simplified = line.simplify(WATERWAY_LINE_TOLERANCE_M * WU_PER_REAL_M, preserve_topology=False)
    if WATERWAY_SMOOTH_ITERATIONS and len(simplified.coords) > 2:
        simplified = LineString(_chaikin(simplified.coords, WATERWAY_SMOOTH_ITERATIONS))
    return simplified.buffer(half_width, resolution=WATERWAY_BUFFER_RESOLUTION)


def _chaikin_ring(coords, iterations: int):
    """Chaikin corner-cutting on a CLOSED ring.

    Differs from _chaikin only in being cyclic: a ring has no endpoints to pin,
    so the first and last vertex are cut like any other. Pinning them instead
    would leave one hard corner per ring, always at whichever vertex OSM
    happened to list first.
    """
    points = list(coords[:-1]) if coords[0] == coords[-1] else list(coords)
    if len(points) < 3:
        return None
    for _ in range(iterations):
        cut = []
        for i, a in enumerate(points):
            b = points[(i + 1) % len(points)]
            cut.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            cut.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        points = cut
    return points + [points[0]]


def _smooth_polygon(poly: Polygon, iterations: int):
    """Chaikin every ring of one polygon, holes included.

    A hole is a boundary between two classes exactly as an exterior is -- the
    class inside the hole is whatever the arrangement labels it -- so leaving
    holes angular would smooth a wood's outline and leave the clearing inside
    it sharp.
    """
    shell = _chaikin_ring(list(poly.exterior.coords), iterations)
    if shell is None:
        return None
    holes = []
    for ring in poly.interiors:
        cut = _chaikin_ring(list(ring.coords), iterations)
        if cut is not None:
            holes.append(cut)
    try:
        out = Polygon(shell, holes)
    except Exception:  # noqa: BLE001 -- a ring too degenerate to close
        return None
    return out if out.is_valid else make_valid(out)


def _despeckle(geom, cls: str):
    """Weld the mosaic, then erase what the weld could not join. Runs BEFORE
    the simplify -- see FIELD_WELD_M for why that order is the whole point.

    Returns the input unchanged for WATERWAY and for an empty geometry. A
    stage that throws or empties the geometry yields the last good version
    rather than dropping the class: a chunk missing its farmland is a much
    worse outcome than a chunk whose farmland is still angular.
    """
    if cls == "WATERWAY" or geom.is_empty:
        return geom
    scale = CONSERVATIVE_FRACTION if cls in CONSERVATIVE_CLASSES else 1.0
    weld = FIELD_WELD_M * scale * WU_PER_REAL_M
    open_d = SLIVER_OPEN_M * scale * WU_PER_REAL_M
    for out_d, back_d in ((weld, -weld), (-open_d, open_d)):
        if out_d == 0.0:
            continue
        try:
            # Round joins, not mitre: mitre extends a sharp reflex corner along
            # its own bisector, which on the spiky input this exists to fix
            # would lengthen the very spikes being removed.
            stepped = geom.buffer(out_d, resolution=CONDITION_BUFFER_RESOLUTION) \
                          .buffer(back_d, resolution=CONDITION_BUFFER_RESOLUTION)
        except Exception:  # noqa: BLE001
            continue
        if not stepped.is_empty and stepped.is_valid:
            geom = stepped
    return geom


def _smooth(geom, cls: str):
    """Chaikin every ring. Runs AFTER the simplify, on purpose.

    Smoothing before the simplify would be pointless work: Douglas-Peucker
    would then pick a subset of the rounded vertices and hand back the same
    angular polyline it always did, which is what the first version of this
    did.
    """
    if cls == "WATERWAY" or not SMOOTH_ITERATIONS or geom.is_empty:
        return geom
    smoothed = [s for s in (_smooth_polygon(p, SMOOTH_ITERATIONS) for p in _parts(geom))
                if s is not None and not s.is_empty]
    if not smoothed:
        return geom
    joined = unary_union(smoothed)
    return joined if not joined.is_empty and joined.is_valid else geom


def _absorb_unclaimed(merged: dict, chunk: Polygon, max_area: float) -> None:
    """Give small isolated pockets of unclaimed ground to a neighbouring class,
    in place. See DEFAULT_ABSORB_AREA_M2.

    "Neighbouring" is decided by SHARED BOUNDARY LENGTH, not by nearest centre
    or by largest neighbour: a pocket wedged between a city and a wood belongs
    to whichever one actually wraps it, and boundary length is the only one of
    the three that says so.
    """
    if not merged:
        return
    try:
        unclaimed = chunk.difference(unary_union(list(merged.values())))
    except Exception:  # noqa: BLE001
        return
    gained: dict[str, list] = {}
    for pocket in _parts(unclaimed):
        if pocket.area >= max_area:
            continue
        best_cls, best_len = None, 0.0
        for cls, geom in merged.items():
            # Never into WATERWAY. A pocket inside a meander is bounded mostly
            # by river, so it would win on shared length every time and the
            # river would silently fatten -- measured 4.77% -> 5.37% of chunk
            # 33,27 before this exemption. That is the same widening
            # WATERWAY_LINE_TOLERANCE_M records, and the ribbon's width is
            # load-bearing for Bridge-mandatory crossing, not just cosmetic.
            if cls == "WATERWAY" or not pocket.intersects(geom):
                continue
            try:
                shared = pocket.boundary.intersection(geom.boundary).length
            except Exception:  # noqa: BLE001
                continue
            if shared > best_len:
                best_cls, best_len = cls, shared
        if best_cls is not None:
            gained.setdefault(best_cls, []).append(pocket)
    for cls, pockets in gained.items():
        grown = unary_union([merged[cls]] + pockets)
        if not grown.is_empty and grown.is_valid:
            merged[cls] = grown


def _drop_small(geom, min_area: float):
    """Remove parts and HOLES below `min_area`.

    Holes matter as much as parts and used not to be filtered at all: a 150m
    gap left inside a wood is not a clearing anyone can see at this scale, it
    is one more sliver -- and because the arrangement labels it by containment
    it comes out as a speck of DEFAULT_CLASS moorland sitting inside the wood.
    """
    kept = []
    for part in _parts(geom):
        if part.area < min_area:
            continue
        holes = [r for r in part.interiors if Polygon(r).area >= min_area]
        kept.append(Polygon(part.exterior, holes) if len(holes) != len(part.interiors) else part)
    if not kept:
        return None
    return unary_union(kept)


def _build_tile_geometry(features: list[dict], transform) -> dict:
    """Classify, project to world space, and build shapely geometry for one
    tile's features.

    Waterway LINES are buffered to a real-world width here rather than being
    left as lines. bake_landcover.py derives its buffer from pixel size and
    says so explicitly -- "the buffer's job is rasterization correctness, not
    modelling true real-world width" -- which is exactly the approximation
    this bake exists to drop.

    The centreline is simplified and smoothed BEFORE it is buffered, so the
    ribbon comes out at a constant width along a rounded path. See
    WATERWAY_LINE_TOLERANCE_M for what happens when the ribbon is simplified
    after buffering instead.
    """
    half_width = WATERWAY_HALF_WIDTH_WU

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
                geom = _waterway_ribbon(LineString(world), half_width)
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
                     tile_names: list[str], land) -> dict | None:
    """Arrangement -> labelled faces -> CDT for one chunk. None if the chunk
    produced no geometry at all."""
    origin_x = chunk_x * CHUNK_SIZE_WU
    origin_y = chunk_y * CHUNK_SIZE_WU
    rect = box(origin_x, origin_y, origin_x + CHUNK_SIZE_WU, origin_y + CHUNK_SIZE_WU)
    # The arrangement domain is (chunk rectangle ∩ real coastline), not the
    # plain rectangle -- everything below (class merging, the boundary
    # network, face labelling, CDT) already operates on whatever `chunk` is,
    # so clipping it here is the entire fix: no other step needs to know
    # land exists. A chunk that is entirely open sea despite passing
    # land_chunks()'s coarser hex-based pre-filter produces nothing, same as
    # a chunk with zero OSM features.
    chunk = set_precision(rect.intersection(land), QUANT_WU)
    if chunk.is_empty:
        return None

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
        # WATERWAY gets a tolerance scaled to its own ribbon width, not the
        # shared one: `tol` is 6.7x the ribbon's full width, which inflates it,
        # pinches it, and breaks the water barrier (see
        # WATERWAY_LINE_TOLERANCE_M). Its centreline was already simplified
        # before buffering, so there is little left here to remove anyway.
        cls_tol = WATERWAY_HALF_WIDTH_WU * WATERWAY_SIMPLIFY_FRACTION if cls == "WATERWAY" else tol
        # Weld the field mosaic and erase slivers BEFORE simplifying, round
        # the corners the simplify leaves AFTER it. See FIELD_WELD_M.
        g = _despeckle(g, cls)
        if g.is_empty:
            continue
        g = _snap(g.simplify(cls_tol, preserve_topology=True))
        if g is None or g.is_empty or not g.is_valid:
            continue
        g = _snap(_smooth(g, cls))
        if g is None or g.is_empty or not g.is_valid:
            continue
        g = _drop_small(g, min_area)
        if g is None:
            continue
        g = g.intersection(chunk)
        if not g.is_empty:
            merged[cls] = g

    # A chunk with no land-cover features at all is not written. It would
    # otherwise bake as a full grid of DEFAULT_CLASS faces -- measured: "0
    # feats, 1225 faces, 4750 tris" -- i.e. 40km of solid default MOORLAND
    # asserted from no evidence whatsoever. These chunks are ground the
    # Overpass/PBF fetch never covered (real open sea within `chunk` was
    # already clipped away above, by the land-polygon intersection, so this
    # case is now specifically "on land but unfetched," not "at sea").
    # Writing nothing lets HexGridMap's flat per-hex tile show through,
    # which is the correct answer for unfetched land.
    if n_features == 0:
        return None

    # Step 2b: hand small isolated pockets of unclaimed ground to a neighbour.
    # After every class has been welded, not before -- the weld is what turns
    # a mosaic of gaps into a few isolated pockets in the first place.
    _absorb_unclaimed(merged, chunk, DEFAULT_ABSORB_AREA_M2 * WU_PER_REAL_M * WU_PER_REAL_M)

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

    # The faces must tile `chunk` (== box ∩ land, since 2026-08-20) exactly,
    # the same partition invariant verify_terrain_mesh.gd polices in-engine --
    # except that verifier compares against the plain CHUNK_SIZE_WU box, which
    # is no longer the right target for a clipped coastal chunk. Its own
    # coverage check now only catches OVERLAP (> 100%); a HOLE is caught here
    # instead, where the real land-clipped area is directly available.
    face_area = sum(f.area for f in faces)
    if chunk.area > 0 and abs(face_area / chunk.area - 1.0) > 0.001:
        print(f"  WARN: chunk {chunk_x},{chunk_y} faces cover {face_area / chunk.area * 100:.2f}% "
              f"of (box ∩ land), expected 100%")

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
         out_dir: str = OUTPUT_DIR, cache_dir: str = OVERPASS_CACHE,
         only_chunks: list[tuple[int, int]] | None = None) -> None:
    print("=== Step 1: fit lon/lat -> world affine ===")
    transform = fit_affine()

    print("\n=== Step 1b: real coastline (Natural Earth GBR+IRL) ===")
    land = land_polygon_world(transform)
    land_parts = land.geoms if hasattr(land, "geoms") else [land]
    land_area_km2 = land.area * (1.0 / WU_PER_REAL_M / 1000.0) ** 2
    print(f"  {len(land_parts)} landmass part(s), area {land_area_km2:,.0f} km2")

    tile_names = sorted(n for n in os.listdir(cache_dir) if n.endswith(".json"))
    # A tile the server genuinely has nothing for comes back as a ~258-byte
    # response whose elements list is empty; keeping it in the list only costs
    # a pointless parse. A tile that FAILED is no longer written at all
    # (fetch_overpass.fetch_tile), so it is absent here rather than
    # indistinguishable from an empty one -- which is what let 22 poisoned
    # tiles bake into flat rectangles before that was fixed.
    tile_names = [n for n in tile_names
                  if os.path.getsize(os.path.join(cache_dir, n)) > 64]
    print(f"\n=== Step 2: {len(tile_names)} non-empty cached tiles ===")

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
    # Blocked iteration, not row-major. A 0.5-degree tile is ~5,640 wu against a
    # 4096 wu chunk, so a full-map row spans ~38 tiles; row-major would evict and
    # reparse essentially every tile once per row, against a cache that holds 8.
    # That is the same cache-thrash shape that once cost 136s of a 156s chunk
    # (tile fetch inside the per-class loop), and at map scale it would dominate
    # the whole bake. A BLOCK_CHUNKS-square block spans ~3x3 tiles, so the
    # working set stays inside the cache and each tile is parsed a handful of
    # times instead of once per row.
    BLOCK_CHUNKS = 4
    all_chunks = []
    for block_y in range(min_cy, max_cy + 1, BLOCK_CHUNKS):
        for block_x in range(min_cx, max_cx + 1, BLOCK_CHUNKS):
            for cy in range(block_y, min(block_y + BLOCK_CHUNKS, max_cy + 1)):
                for cx in range(block_x, min(block_x + BLOCK_CHUNKS, max_cx + 1)):
                    all_chunks.append((cx, cy))
    keep = land_chunks()
    before = len(all_chunks)
    full_grid = all_chunks

    # land_chunks() alone is NOT a safe superset of the real coastline -- measured,
    # not assumed: it is a coarse, cheap first pass off _LAND_RLE's hex mask, and
    # _LAND_RLE comes from a different, lost transform than the affine every other
    # class here (including the new coastline) is fit against (see coastline.py's
    # own doc comment). A chunk land_chunks() calls pure sea can still be touched
    # by the real, freshly-projected coastline -- first full-map trial run found
    # 67 such chunks, real coastal ground that would otherwise never reach
    # build_chunk_mesh() at all, not just be mislabeled inside it. So the grid is
    # the UNION of both: land_chunks()'s candidates (cheap, keeps the common case
    # fast) plus any chunk the real landmass's envelope overlaps (STRtree query,
    # bounding-box precision -- a false positive here just costs one fast empty
    # build_chunk_mesh() call, not a correctness risk, since the exact intersection
    # is still what decides the chunk's actual content).
    land_tree = STRtree(land_parts)
    real_touch = {c for c in full_grid
                  if len(land_tree.query(box(c[0] * CHUNK_SIZE_WU, c[1] * CHUNK_SIZE_WU,
                                             (c[0] + 1) * CHUNK_SIZE_WU, (c[1] + 1) * CHUNK_SIZE_WU)))}
    missed = sorted(real_touch - keep)
    all_chunks = [c for c in all_chunks if c in keep or c in real_touch]
    print(f"  {before} chunks in the grid, {len(all_chunks)} contain land "
          f"({before - len(all_chunks)} pure-sea chunks skipped)")
    if missed:
        print(f"  land_chunks() (_LAND_RLE) alone would have skipped {len(missed)} chunk(s) the "
              f"real coastline touches -- added back: {missed[:10]}{' ...' if len(missed) > 10 else ''}")
    else:
        print("  land_chunks() (_LAND_RLE) agrees: no chunk it skipped is touched by the real coastline")

    if only_chunks:
        # Explicit addresses bypass the grid entirely rather than filtering it,
        # so a named chunk still bakes when it falls outside the default
        # corridor range -- the point of --chunks is sweeping a constant on one
        # known-interesting chunk without also knowing which q/r covers it.
        all_chunks = list(only_chunks)
        print(f"  --chunks overrides the grid: {all_chunks}")
    if limit is not None:
        all_chunks = all_chunks[:limit]
    print(f"q={q_range} r={r_range} -> chunk grid x {min_cx}..{max_cx}, y {min_cy}..{max_cy} "
          f"({len(all_chunks)} chunks of {CHUNK_SIZE_WU:.0f} wu)")

    os.makedirs(out_dir, exist_ok=True)
    cache = _TileGeometryCache(cache_dir)

    print(f"\n=== Step 3: bake {len(all_chunks)} chunks ===")
    written = skipped = 0
    total_bytes = total_tris = total_verts = 0
    max_verts_seen = 0
    started = time.time()
    for n, (cx, cy) in enumerate(all_chunks, start=1):
        t0 = time.time()
        try:
            mesh = build_chunk_mesh(cx, cy, transform, cache, tile_names, land)
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
              f"(the square ground this replaced drew 242 tris/hex)")
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
    ap.add_argument("--cache", default=OVERPASS_CACHE,
                    help="tile cache to read (default: the Overpass one; pass "
                         "cache/tiles_pbf for the full GB+Ireland extract)")
    ap.add_argument("--full-map", action="store_true",
                    help="cover BritishGeographyData.MAP_BOUNDS instead of the corridor. "
                         "Only useful with a --cache that actually spans it")
    ap.add_argument("--chunks", nargs="+", metavar="X,Y",
                    help="bake only these chunk addresses, ignoring --q/--r. For sweeping a "
                         "boundary-conditioning constant on one chunk instead of a 60-minute map")
    # Overrides so a sweep is one command per value rather than an edit per
    # value -- every one of these was chosen by baking a few settings of it
    # onto the same chunk and looking at preview_chunk_mesh.py's output.
    ap.add_argument("--weld", type=float, help=f"FIELD_WELD_M (default {FIELD_WELD_M})")
    ap.add_argument("--open", type=float, dest="open_m",
                    help=f"SLIVER_OPEN_M (default {SLIVER_OPEN_M})")
    ap.add_argument("--smooth", type=int, help=f"SMOOTH_ITERATIONS (default {SMOOTH_ITERATIONS})")
    ap.add_argument("--tolerance", type=float,
                    help=f"SIMPLIFY_TOLERANCE_M (default {SIMPLIFY_TOLERANCE_M})")
    args = ap.parse_args()
    for name, value in (("FIELD_WELD_M", args.weld), ("SLIVER_OPEN_M", args.open_m),
                        ("SMOOTH_ITERATIONS", args.smooth),
                        ("SIMPLIFY_TOLERANCE_M", args.tolerance)):
        if value is not None:
            globals()[name] = value
            print(f"  override {name} = {value}")
    only_chunks = None
    if args.chunks:
        only_chunks = [tuple(int(p) for p in c.split(",")) for c in args.chunks]
    q_range, r_range = tuple(args.q), tuple(args.r)
    if args.full_map:
        # BritishGeographyData.MAP_BOUNDS = Rect2i(0, 0, 154, 179), inclusive of
        # its last row/column. Kept here rather than imported because that value
        # lives in GDScript; if it moves, this is the one line to follow it.
        q_range, r_range = (0, 153), (0, 178)
    bake(q_range, r_range, limit=args.limit, out_dir=args.out, cache_dir=args.cache,
         only_chunks=only_chunks)
