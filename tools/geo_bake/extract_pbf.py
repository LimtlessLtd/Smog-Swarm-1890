"""Extract this bake's land-cover/water features from Geofabrik .osm.pbf
extracts into the same per-tile cache format fetch_overpass.py writes.

    python tools/geo_bake/extract_pbf.py \
        --pbf tools/geo_bake/cache/pbf/great-britain.osm.pbf \
              tools/geo_bake/cache/pbf/ireland-and-northern-ireland.osm.pbf \
        --out tools/geo_bake/cache/tiles_pbf

Epic phase 1c. The Overpass path cannot reach full GB+Ireland coverage: it is a
shared public instance that answers 504 on dense ground, needs a courtesy delay
per request, and its fetched bbox came from the projection's calibration points
rather than the map's own extent -- which left 41.3% of the map's land hexes
with any baked mesh at all. A Geofabrik extract is the whole country in one
local file, so coverage stops being a function of how much the server will
tolerate.

WHY THE SAME TILE FORMAT. bake_vector_landcover.py discovers its inputs by
listing a cache directory and parsing each filename's bbox, then reads Overpass
`out geom` JSON. Emitting exactly that means the bake does not learn where its
data came from, and the Overpass cache stays usable side by side for comparison
-- which is worth having, since this changes the data source under a pipeline
whose output was already verified against the other one.

TILE ASSIGNMENT mirrors Overpass's own behaviour: a bbox query returns every
way INTERSECTING the box, not just those contained in it, so a way here is
written to every tile its bounding box touches. Long rivers are therefore
duplicated across tiles, exactly as before; the bake unions per chunk, so
duplicates cost parse time and change no geometry.

RELATIONS are split, not grouped. Overpass returns one relation element with
many member geometries; fetch_overpass.elements_to_features() then emits one
feature per member ring regardless. So a member way is written here as its own
single-member relation element carrying the parent's tags, which produces an
identical feature list without having to hold a whole country's relations in
memory to reassemble them. It inherits the same documented approximation --
inner and outer rings are not distinguished -- because that is what the
consumer does with them.
"""

import argparse
import json
import os
import sys
import time

import osmium
import osmium.filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fetch_overpass import _fmt_coord  # noqa: E402  -- one source of truth for the tile filename convention.

# Must match fetch_overpass._QUERY_TEMPLATE exactly. A mismatch would not
# error, it would silently bake different terrain from the same map.
LANDUSE = {"forest", "farmland", "orchard", "meadow", "allotments", "residential",
           "commercial", "retail", "industrial", "construction", "farmyard"}
NATURAL_WAY = {"wood", "wetland", "heath", "water", "scrub"}
NATURAL_RELATION = {"wood", "wetland", "water"}
WATERWAY = {"river", "canal"}

TILE_DEGREES = 0.5

## Open .jsonl handles kept at once. Every element is appended to one file per
## tile it touches, so this streams instead of holding a country in memory; the
## cap keeps the process well under any OS handle limit when a long way sprays
## across dozens of tiles.
MAX_OPEN_TILES = 192


def _matches_way(tags) -> bool:
    if tags.get("landuse") in LANDUSE:
        return True
    if tags.get("natural") in NATURAL_WAY:
        return True
    waterway = tags.get("waterway")
    if waterway in WATERWAY:
        return True
    # waterway=stream is restricted to NAMED streams, matching the Overpass
    # query's own filter: UK OSM maps field drains exhaustively as unnamed
    # streams, and including them flooded roughly 2/3 of a validation raster
    # with water at this game's ~25-sq-mi/hex scale.
    return waterway == "stream" and bool(tags.get("name"))


class _TileWriter:
    """Appends elements to one .jsonl per tile, keeping only a bounded number
    of file handles open."""

    def __init__(self, out_dir: str):
        self.out_dir = out_dir
        self._open: dict[tuple, object] = {}
        self._order: list[tuple] = []
        self.written = 0

    def _handle(self, key: tuple):
        handle = self._open.get(key)
        if handle is not None:
            return handle
        while len(self._order) >= MAX_OPEN_TILES:
            self._open.pop(self._order.pop(0)).close()
        # Append, not write: a tile is reopened whenever it falls out of the
        # LRU, and a second .pbf (Ireland) adds to tiles Great Britain already
        # touched along the Irish Sea.
        handle = open(os.path.join(self.out_dir, self._name(key)), "a", encoding="utf-8")
        self._open[key] = handle
        self._order.append(key)
        return handle

    @staticmethod
    def _name(key: tuple) -> str:
        lat_i, lon_i = key
        lat, lon = lat_i * TILE_DEGREES, lon_i * TILE_DEGREES
        return "_".join(_fmt_coord(v) for v in
                        (lat, lon, lat + TILE_DEGREES, lon + TILE_DEGREES)) + ".jsonl"

    def add(self, element: dict, bbox: tuple) -> None:
        min_lon, min_lat, max_lon, max_lat = bbox
        line = json.dumps(element, separators=(",", ":"))
        for lat_i in range(int(min_lat // TILE_DEGREES), int(max_lat // TILE_DEGREES) + 1):
            for lon_i in range(int(min_lon // TILE_DEGREES), int(max_lon // TILE_DEGREES) + 1):
                self._handle((lat_i, lon_i)).write(line + "\n")
                self.written += 1

    def close(self) -> None:
        for handle in self._open.values():
            handle.close()
        self._open.clear()
        self._order.clear()


def collect_relation_members(path: str) -> tuple[dict, dict]:
    """way id -> [relation id], and relation id -> tags, for the relations this
    bake consumes. Separate pass because a relation's members are ways that may
    appear anywhere in the file, including before the relation itself."""
    way_to_rels: dict[int, list[int]] = {}
    rel_tags: dict[int, dict] = {}
    processor = (osmium.FileProcessor(path)
                 .with_filter(osmium.filter.EntityFilter(osmium.osm.RELATION)))
    for rel in processor:
        if rel.tags.get("natural") not in NATURAL_RELATION:
            continue
        rel_tags[rel.id] = dict(rel.tags)
        for member in rel.members:
            if member.type == "w":
                way_to_rels.setdefault(member.ref, []).append(rel.id)
    return way_to_rels, rel_tags


def extract(path: str, writer: _TileWriter, storage: str) -> dict:
    started = time.time()
    print(f"  pass 1/2: relation members of {os.path.basename(path)}", flush=True)
    way_to_rels, rel_tags = collect_relation_members(path)
    print(f"    {len(rel_tags)} relations, {len(way_to_rels)} member ways "
          f"({time.time() - started:.0f}s)", flush=True)

    print(f"  pass 2/2: ways (with node locations, storage={storage})", flush=True)
    counts = {"way": 0, "relation_member": 0, "incomplete": 0}
    processor = (osmium.FileProcessor(path)
                 .with_filter(osmium.filter.EntityFilter(osmium.osm.WAY))
                 .with_locations(storage))
    for way in processor:
        as_way = _matches_way(way.tags)
        parents = way_to_rels.get(way.id)
        if not as_way and not parents:
            continue
        try:
            ring = [{"lon": n.lon, "lat": n.lat} for n in way.nodes if n.location.valid()]
        except osmium.InvalidLocationError:
            counts["incomplete"] += 1
            continue
        if len(ring) < 2:
            counts["incomplete"] += 1
            continue
        lons = [p["lon"] for p in ring]
        lats = [p["lat"] for p in ring]
        bbox = (min(lons), min(lats), max(lons), max(lats))
        if as_way:
            writer.add({"type": "way", "tags": dict(way.tags), "geometry": ring}, bbox)
            counts["way"] += 1
        for rel_id in parents or ():
            writer.add({"type": "relation", "tags": rel_tags[rel_id],
                        "members": [{"geometry": ring}]}, bbox)
            counts["relation_member"] += 1
    print(f"    {counts['way']} ways, {counts['relation_member']} relation members, "
          f"{counts['incomplete']} skipped for missing node locations "
          f"({time.time() - started:.0f}s)", flush=True)
    return counts


def finalise(out_dir: str) -> None:
    """Fold each tile's .jsonl into the Overpass-shaped .json the bake reads."""
    names = sorted(n for n in os.listdir(out_dir) if n.endswith(".jsonl"))
    print(f"\n=== Folding {len(names)} tiles into Overpass-shaped JSON ===", flush=True)
    total_bytes = 0
    for i, name in enumerate(names, 1):
        src = os.path.join(out_dir, name)
        dst = src[:-len(".jsonl")] + ".json"
        with open(src, "r", encoding="utf-8") as f_in, open(dst, "w", encoding="utf-8") as f_out:
            f_out.write('{"elements":[')
            for j, line in enumerate(f_in):
                line = line.strip()
                if not line:
                    continue
                if j:
                    f_out.write(",")
                f_out.write(line)
            f_out.write("]}")
        os.remove(src)
        total_bytes += os.path.getsize(dst)
        if i % 100 == 0 or i == len(names):
            print(f"  {i}/{len(names)} tiles, {total_bytes / 1024 / 1024:.0f} MB", flush=True)
    print(f"  {len(names)} tiles, {total_bytes / 1024 / 1024:.0f} MB total")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--storage", default="flex_mem",
                    help="pyosmium node-location index. flex_mem holds it in RAM; pass "
                         "'sparse_file_array,<path>' to spill to disk on a smaller machine.")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    stale = [n for n in os.listdir(args.out) if n.endswith((".json", ".jsonl"))]
    for name in stale:
        os.remove(os.path.join(args.out, name))
    if stale:
        print(f"Cleared {len(stale)} files from a previous run "
              f"(they would otherwise be appended to, silently doubling features)")

    writer = _TileWriter(args.out)
    started = time.time()
    for path in args.pbf:
        print(f"\n=== {os.path.basename(path)} "
              f"({os.path.getsize(path) / 1024 / 1024:.0f} MB) ===", flush=True)
        extract(path, writer, args.storage)
    writer.close()
    print(f"\n{writer.written} tile-writes in {(time.time() - started) / 60:.1f} min")
    finalise(args.out)


if __name__ == "__main__":
    main()
