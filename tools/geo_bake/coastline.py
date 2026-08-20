"""Real coastline boundary for GB + Ireland, from Natural Earth's public-
domain 1:10m Admin-0 Countries dataset -- the source BritishGeographyData.gd's
own header comment already names for the lost original coastline bake
("7,113 points across GB's 57 sub-polygons, 2,394 across Ireland's 7"), and
geo_projection.py's own docstring names re-baking it as a planned consumer of
fit_affine().

Confirmed reachable this session: the GitHub-hosted mirror of Natural Earth
(nvkelso/natural-earth-vector), 13.3 MB, a single static file -- not a
tiled/rate-limited API like Overpass, so no subdivide-on-failure logic is
needed here, just a fetch-once-and-cache.

GBR (Great Britain + Northern Ireland) and IRL (Republic of Ireland) are
UNIONED rather than using GBR alone. That dissolves their shared land
border (Northern Ireland / Republic of Ireland) as an interior seam of the
union, so the result is the real coastline, not a country outline with an
inland edge down the middle of Ireland.

Not guaranteed to agree with BritishGeographyData._LAND_RLE: this fits the
SAME affine (geo_projection.fit_affine()) every other vector-terrain bake
already uses, but _LAND_RLE came from a different, undocumented, lost
transform (see geo_projection.py's own docstring). Measure the disagreement
before trusting a full re-bake -- see todo.md's "1b" entry.
"""

import io
import json
import os
import urllib.request

from shapely.geometry import Polygon, shape
from shapely.ops import unary_union

from geo_projection import apply_affine

_CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache", "natural_earth")
_CACHE_PATH = os.path.join(_CACHE_DIR, "ne_10m_admin_0_countries.geojson")
_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
        "master/geojson/ne_10m_admin_0_countries.geojson")

_COUNTRY_CODES = {"GBR", "IRL"}


def fetch_countries_geojson() -> dict:
    """(Down)load the full Natural Earth Admin-0 Countries GeoJSON.

    One static file, not a tiled API -- no per-tile retry/subdivide logic
    the way fetch_overpass.py needs. A failed fetch raises rather than
    caching anything: there is only ever one file here, so a bad partial
    write would poison every future run identically rather than costing one
    re-fetched tile.
    """
    os.makedirs(_CACHE_DIR, exist_ok=True)
    if os.path.exists(_CACHE_PATH):
        with io.open(_CACHE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)

    req = urllib.request.Request(
        _URL,
        headers={"User-Agent": "smog-swarm-1890-terrain-bake/1.0 (offline one-time data bake script)"},
    )
    print(f"  fetching {_URL} ...", flush=True)
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    # Written only after a full successful read -- a partial/truncated
    # response must not leave a truncated file that a later run trusts as
    # already-cached, the same "never cache a failure" rule
    # fetch_overpass.py established for its tiles.
    with io.open(_CACHE_PATH, "wb") as f:
        f.write(raw)
    return json.loads(raw.decode("utf-8"))


def land_polygon_lonlat():
    """GBR union IRL as one (Multi)Polygon in lon/lat.

    Every real island is kept -- Natural Earth's country polygons are
    already MultiPolygons at this resolution, not just the mainland outline
    -- and the union dissolves the internal Northern Ireland/Republic of
    Ireland land border rather than leaving it as a seam.
    """
    data = fetch_countries_geojson()
    geoms = []
    for feature in data["features"]:
        if feature.get("properties", {}).get("ADM0_A3") in _COUNTRY_CODES:
            geoms.append(shape(feature["geometry"]))
    if not geoms:
        raise SystemExit("no GBR/IRL features found in the Natural Earth Admin-0 "
                          "Countries data -- has ADM0_A3 or the dataset's field names changed?")
    return unary_union(geoms)


def land_polygon_world(transform):
    """The same landmass polygon, projected into world units via
    geo_projection.apply_affine(transform, lon, lat) -- the identical
    lon/lat -> world-space transform every other class in
    bake_vector_landcover.py already uses, so this lands in the same
    coordinate space the chunk boxes it gets intersected against use.

    Points are projected before the parts are re-unioned, matching
    _build_tile_geometry()'s existing per-ring project-then-build pattern
    (the affine is linear, so projecting before or after unioning is
    equivalent either way).
    """
    lonlat = land_polygon_lonlat()
    parts = lonlat.geoms if hasattr(lonlat, "geoms") else [lonlat]
    projected = []
    for part in parts:
        exterior = [apply_affine(transform, lon, lat) for lon, lat in part.exterior.coords]
        interiors = [[apply_affine(transform, lon, lat) for lon, lat in ring.coords]
                     for ring in part.interiors]
        projected.append(Polygon(exterior, interiors))
    return unary_union(projected)


if __name__ == "__main__":
    from geo_projection import fit_affine

    t = fit_affine()
    land = land_polygon_world(t)
    parts = land.geoms if hasattr(land, "geoms") else [land]
    print(f"land polygon: {len(parts)} part(s), area {land.area:,.0f} wu2, bounds {land.bounds}")
