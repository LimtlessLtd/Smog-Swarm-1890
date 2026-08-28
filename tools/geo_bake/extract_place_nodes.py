"""Extract OSM settlement POINTS (place nodes) from the Geofabrik .osm.pbf
extracts into one cached JSON list.

    python tools/geo_bake/extract_place_nodes.py \
        --pbf tools/geo_bake/cache/pbf/great-britain.osm.pbf \
              tools/geo_bake/cache/pbf/ireland-and-northern-ireland.osm.pbf \
        --out tools/geo_bake/cache/places/place_nodes.json

WHY A SEPARATE PASS AND A SEPARATE CACHE. extract_pbf.py already reads the same
two files, but it filters `osmium.osm.WAY` / `osmium.osm.RELATION` only, so a
node is never yielded to its loop at all, and its tag test (`_matches_way()`)
covers landuse/natural/waterway with no `place` clause. Measured against the
live cache before this file existed: `cache/tiles_pbf` holds ZERO elements of
type "node" across 282 tiles / 3.0 GB, and the string `population` appears nine
times in the whole cache -- every one of them incidental, on a landuse way that
happens to also carry the tag. Re-reading that cache would produce a near-empty
population map that still looked like it ran.

It writes somewhere else on purpose. extract_pbf.py deletes every .json/.jsonl
in its `--out` at startup (they would otherwise be appended to), and its tag
sets must stay identical to fetch_overpass._QUERY_TEMPLATE or the two sources
silently bake different terrain from the same map. Adding place nodes to that
directory would break both invariants.

NO .with_locations(). A node carries its own location, so the flex_mem node
index -- the expensive half of extract_pbf.py's way pass -- is not needed here.
Both extracts scan in about seven seconds.

PLACE KINDS. Only the four that name a distinct inhabited settlement are kept:
city, town, village, hamlet. `suburb`/`borough`/`neighbourhood`/`quarter` are
deliberately excluded -- they sit INSIDE a settlement whose own node already
carries the whole population, so keeping them double-counts. Measured on the
2026-08-28 extracts: 6,196 suburb nodes, of which the 127 tagged ones have a
median population of 7,729; filling the untagged 6,069 from that median added a
phantom 47 million people to a 37 million country. `locality` (47,825 nodes) and
`isolated_dwelling` are excluded for the opposite reason: a locality is a named
place, not necessarily an inhabited one.
"""

import argparse
import io
import json
import os
import time

import osmium
import osmium.filter

## design_doc.md 2.1 wants "how many zombies this hex can hold" from real
## settlement population. These four are the OSM place values that denote an
## inhabited settlement in its own right -- see this file's own doc comment for
## why suburb/locality and friends are not here.
PLACE_KINDS = {"city", "town", "village", "hamlet"}


def extract(pbf_paths: list, out_path: str) -> int:
    places = []
    kinds = {}
    with_pop = {}
    started = time.time()

    for path in pbf_paths:
        if not os.path.exists(path):
            raise SystemExit(f"missing extract {path} -- download the Geofabrik .osm.pbf first")
        before = len(places)
        processor = (osmium.FileProcessor(path, osmium.osm.NODE)
                     .with_filter(osmium.filter.KeyFilter("place")))
        for node in processor:
            kind = node.tags.get("place")
            if kind not in PLACE_KINDS:
                continue
            population = node.tags.get("population")
            kinds[kind] = kinds.get(kind, 0) + 1
            if population:
                with_pop[kind] = with_pop.get(kind, 0) + 1
            places.append({
                "name": node.tags.get("name") or node.tags.get("name:en") or "",
                "place": kind,
                # Kept as the raw tag string. It is free text in OSM ("12,345",
                # "~800", "1500 (2011)"), so parsing belongs in the consumer
                # that has to decide what to do with an unparseable one.
                "population": population,
                "wikidata": node.tags.get("wikidata") or "",
                "lon": node.location.lon,
                "lat": node.location.lat,
            })
        print(f"  {os.path.basename(path)}: {len(places) - before:,} place nodes"
              f"  ({time.time() - started:.0f}s)", flush=True)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    # encoding="utf-8" is load-bearing on Windows: Welsh and Irish place names
    # carry characters cp1252 cannot encode, and the default open() there
    # raises UnicodeEncodeError partway through a 100k-entry dump.
    with io.open(out_path, "w", encoding="utf-8") as f:
        json.dump(places, f, ensure_ascii=False)

    print("\nplace kind           nodes   with a population tag")
    for kind in sorted(kinds, key=lambda k: -kinds[k]):
        print(f"  {kind:12s} {kinds[kind]:9,d} {with_pop.get(kind, 0):12,d}")
    print(f"\nwrote {out_path} ({os.path.getsize(out_path):,} bytes, "
          f"{len(places):,} places, {sum(with_pop.values()):,} with population) "
          f"in {time.time() - started:.0f}s")
    return len(places)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", nargs="+", default=[
        os.path.join(here, "cache", "pbf", "great-britain.osm.pbf"),
        os.path.join(here, "cache", "pbf", "ireland-and-northern-ireland.osm.pbf"),
    ])
    parser.add_argument("--out", default=os.path.join(here, "cache", "places", "place_nodes.json"))
    args = parser.parse_args()
    extract(args.pbf, args.out)
