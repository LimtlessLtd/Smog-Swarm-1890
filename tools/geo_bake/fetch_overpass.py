"""OpenStreetMap Overpass API fetcher for real land-cover/water polygon
data. https://overpass-api.de/api/interpreter, no auth, worldwide,
ODbL licensed (requires "(c) OpenStreetMap contributors" attribution
somewhere in the shipped game -- flagged for todo.md, not solved here).

Confirmed reachable this session with a live test query. Returns real
vector way/relation geometry via `out geom`, which inlines every node's
lat/lon directly in the response -- no second recursive `>` query
needed, and no local node-ID cross-referencing required.

Queries are tiled into small bboxes and cached to disk (gitignored)
so a long bake run is resumable and doesn't hammer the shared public
Overpass instance.
"""

import json
import math
import os
import time
import urllib.request

_CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache", "overpass")
_ENDPOINT = "https://overpass-api.de/api/interpreter"

# landuse/natural/waterway tags this bake actually consumes, mapped to a
# small internal class name (see bake_landcover.py for the class ->
# GameEnums.BiomeType mapping table).
#
# waterway=stream is DELIBERATELY restricted to named streams only — a
# live diagnostic this bake session found 4,015 of 4,602 waterway
# features in one small test area were "stream," and 75% of THOSE carry
# no name tag at all. That's overwhelmingly UK OSM's exhaustive field-
# drain/ditch mapping, not meaningful watercourses at this game's
# ~25-sq-mi/hex scale — including them unfiltered flooded roughly 2/3 of
# a validation raster with WATERWAY. river/canal stay unrestricted (both
# are always a real, game-scale-relevant feature).
_QUERY_TEMPLATE = """
[out:json][timeout:60];
(
  way["landuse"~"^(forest|farmland|orchard|meadow|allotments|residential|commercial|retail|industrial|construction|farmyard)$"]({bbox});
  way["natural"~"^(wood|wetland|heath|water|scrub)$"]({bbox});
  relation["natural"~"^(wood|wetland|water)$"]({bbox});
  way["waterway"~"^(river|canal)$"]({bbox});
  way["waterway"="stream"]["name"]({bbox});
);
out geom;
""".strip()


## Shortest exact decimal that still carries a decimal point. The point
## matters only for backward compatibility: every tile cached before
## subdivision existed was written with "%.1f", so an integer-valued
## coordinate has to stay "-2.0" and not become "-2" or four already-fetched
## tiles orphan themselves. Everything else is unchanged ("51.3" -> "51.3"),
## and a subdivided coordinate now survives that could not before ("51.55"
## would have collided with 51.5 under "%.1f").
def _fmt_coord(value: float) -> str:
    text = f"{value:g}"
    return text if "." in text else f"{text}.0"


def _cache_path(min_lat: float, min_lon: float, max_lat: float, max_lon: float) -> str:
    name = "_".join(_fmt_coord(v) for v in (min_lat, min_lon, max_lat, max_lon)) + ".json"
    return os.path.join(_CACHE_DIR, name)


def fetch_tile(min_lat: float, min_lon: float, max_lat: float, max_lon: float) -> dict:
    """Fetch (or load from cache) one bbox's worth of OSM land-cover/water data.

    Returns an empty result on failure; see the comment at the bottom for why
    that empty result is deliberately NOT cached.
    """
    os.makedirs(_CACHE_DIR, exist_ok=True)
    path = _cache_path(min_lat, min_lon, max_lat, max_lon)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    bbox = f"{min_lat},{min_lon},{max_lat},{max_lon}"
    query = _QUERY_TEMPLATE.format(bbox=bbox)
    data = query.encode("utf-8")
    req = urllib.request.Request(
        _ENDPOINT,
        data=data,
        method="POST",
        headers={
            "Content-Type": "text/plain; charset=utf-8",
            "User-Agent": "smog-swarm-1890-terrain-bake/1.0 (offline one-time data bake script)",
            "Accept": "*/*",
        },
    )
    # Retry with backoff on 429 (rate limited) / 504 (server-side query
    # timeout, common on the shared public instance under load) -- a
    # silently-empty tile from either of these would leave a real gap in
    # the baked land-cover data, not just a slow fetch. Kept SHORT
    # (2 attempts, modest backoff, 45s per-request timeout) after this
    # bake session found the public instance intermittently slow to the
    # point that a longer retry policy (4 attempts, up to 90s each) could
    # stall on a single stubborn tile for several minutes -- a smaller
    # 0.5-degree tile_degrees (see fetch_bbox_tiled's own default) is the
    # main fix for reliability; this is just a bound on the worst case,
    # not the primary lever. A tile that still fails after 2 tries returns
    # empty for THIS run rather than blocking the rest of a long
    # corridor-wide run -- but it is NOT written to the cache. See below.
    result = None
    for attempt in range(2):
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                result = json.loads(resp.read().decode("utf-8"))
            break
        except Exception as exc:  # noqa: BLE001
            wait = 4.0 * (2 ** attempt)
            print(f"  WARN: Overpass tile {bbox} attempt {attempt + 1} failed ({exc}), retrying in {wait:.0f}s", flush=True)
            time.sleep(wait)

    # A FAILED tile is never cached. Writing `{"elements": []}` on failure
    # makes a network error indistinguishable from ground that genuinely
    # has no mapped features, and the cache-hit path above then returns it
    # forever -- the tile is poisoned and no re-run can heal it. 22 of the
    # 113 cached tiles were poisoned exactly this way, including south
    # Manchester, Liverpool, Oxford and the Peak District, and each one
    # bakes into a 40x40 km rectangle of flat default MOORLAND. That was
    # survivable when the rasters were the product and the cost was a
    # slightly wrong pixel; the vector mesh IS the terrain, so it is not.
    # Not writing means the next run retries, which is what "resumable"
    # has to mean for a fetch that can fail.
    if result is None:
        print(f"  ERROR: Overpass tile {bbox} failed after all retries -- NOT cached, re-run to retry", flush=True)
        return {"elements": []}

    with open(path, "w", encoding="utf-8") as f:
        json.dump(result, f)
    time.sleep(2.0)  # courtesy delay -- shared public instance
    return result


## Smallest bbox edge, in degrees, that subdivision will produce. ~7 km of
## latitude. Started at 0.125 and had to come down: Liverpool and the
## Manchester/Peak fringe still answered 504 at 0.15 degrees, which is the
## first split of a 0.3-degree tile, so the floor was stopping subdivision
## one step before the size that actually works over the densest ground.
_MIN_SUBDIVIDE_DEGREES = 0.0625


def fetch_tile_subdivided(min_lat: float, min_lon: float, max_lat: float, max_lon: float,
                          _depth: int = 0) -> dict:
    """fetch_tile, but a failure splits the bbox into quadrants and retries
    each, down to _MIN_SUBDIVIDE_DEGREES.

    The public Overpass instance answers 504 Gateway Timeout when a query
    covers too much dense ground, which is not a transient error -- retrying
    the same 0.5-degree bbox over Manchester or north-west London fails again
    every time, which is how those tiles came to be missing in the first
    place. Quartering the area is the lever that actually works.

    Each quadrant caches under its own name, and the cache is addressed by
    bbox rather than by a fixed grid, so a subdivided region is discovered by
    a later bake exactly like any other tile. Returns the merged elements.
    """
    mid_lat = (min_lat + max_lat) / 2.0
    mid_lon = (min_lon + max_lon) / 2.0
    quadrants = [(lo_lat, lo_lon, hi_lat, hi_lon)
                 for lo_lat, hi_lat in ((min_lat, mid_lat), (mid_lat, max_lat))
                 for lo_lon, hi_lon in ((min_lon, mid_lon), (mid_lon, max_lon))]

    # A bbox that succeeded only after splitting has no cache file of its own,
    # only its quadrants'. Without this check, every later run re-requests the
    # parent, waits out both retries and both backoffs, and fails again before
    # reaching the quadrants it already has -- resumption would cost a
    # guaranteed ~15s per healed tile forever.
    already_split = any(os.path.exists(_cache_path(*q)) for q in quadrants)
    if not already_split:
        result = fetch_tile(min_lat, min_lon, max_lat, max_lon)
        if os.path.exists(_cache_path(min_lat, min_lon, max_lat, max_lon)):
            return result

    span = min(max_lat - min_lat, max_lon - min_lon)
    if span / 2.0 < _MIN_SUBDIVIDE_DEGREES:
        print(f"  ERROR: {min_lat},{min_lon},{max_lat},{max_lon} failed at the "
              f"{span:g}-degree subdivision floor -- left uncached", flush=True)
        return {"elements": []}

    if not already_split:
        print(f"  splitting {min_lat},{min_lon},{max_lat},{max_lon} into quadrants", flush=True)
    merged: list = []
    for quadrant in quadrants:
        merged.extend(fetch_tile_subdivided(*quadrant, _depth + 1).get("elements", []))
    return {"elements": merged}


def elements_to_features(result: dict) -> list[dict]:
    """Normalize raw Overpass `out geom` elements into a flat list of
    {tags, kind ('way'|'relation'), rings: [[(lon,lat), ...], ...]}.

    A `way` contributes one ring (its own geometry, closed or not --
    waterways are open lines, landuse/natural ways are closed polygons).
    A `relation` (multipolygon) contributes one ring per member way that
    itself carries geometry -- an approximation (doesn't distinguish
    inner/outer rings) that's fine for this bake's coarse land-cover
    classification, not fine enough for anything requiring exact area.
    """
    out = []
    for el in result.get("elements", []):
        tags = el.get("tags", {})
        if el["type"] == "way" and "geometry" in el:
            ring = [(pt["lon"], pt["lat"]) for pt in el["geometry"]]
            if len(ring) >= 2:
                out.append({"tags": tags, "kind": "way", "ring": ring})
        elif el["type"] == "relation":
            for member in el.get("members", []):
                if "geometry" in member:
                    ring = [(pt["lon"], pt["lat"]) for pt in member["geometry"]]
                    if len(ring) >= 3:
                        out.append({"tags": tags, "kind": "relation", "ring": ring})
    return out


def fetch_bbox_tiled(min_lat: float, min_lon: float, max_lat: float, max_lon: float,
                      tile_degrees: float = 1.0) -> list[dict]:
    """Tile a big bbox into `tile_degrees` squares, fetch each, flatten."""
    total_tiles = math.ceil((max_lat - min_lat) / tile_degrees) * math.ceil((max_lon - min_lon) / tile_degrees)
    features: list[dict] = []
    lat = min_lat
    n_tiles = 0
    while lat < max_lat:
        lon = min_lon
        lat_hi = min(lat + tile_degrees, max_lat)
        while lon < max_lon:
            lon_hi = min(lon + tile_degrees, max_lon)
            n_tiles += 1
            result = fetch_tile(lat, lon, lat_hi, lon_hi)
            new_features = elements_to_features(result)
            features.extend(new_features)
            print(f"  tile {n_tiles}/{total_tiles} ({lat:.2f},{lon:.2f}): {len(new_features)} features, {len(features)} total", flush=True)
            lon = lon_hi
        lat = lat_hi
    print(f"  fetched/cached {n_tiles} Overpass tiles, {len(features)} features total", flush=True)
    return features


if __name__ == "__main__":
    # Tiny live smoke test over central Manchester (already proven reachable
    # this session) -- confirms the module end to end without a full bake.
    feats = fetch_bbox_tiled(53.47, -2.26, 53.49, -2.23, tile_degrees=1.0)
    kinds = {}
    for f in feats:
        key = f["tags"].get("landuse") or f["tags"].get("natural") or f["tags"].get("waterway") or "?"
        kinds[key] = kinds.get(key, 0) + 1
    print("Tag histogram:", kinds)
