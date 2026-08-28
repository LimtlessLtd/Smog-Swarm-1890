"""Bake `total_zombie_pop` -- one 1890s-population capacity per macro-hex --
for the whole map, from real settlement data.

    python tools/geo_bake/extract_place_nodes.py          # once, ~10 s
    python tools/geo_bake/fetch_wikidata_population.py    # once, ~20 s
    python tools/geo_bake/bake_population.py

Output: assets/terrain_data/zombie_population.zpop, read by
scripts/world/data/ZombiePopulationData.gd.

design_doc.md 2.1: "`total_zombie_pop` *(int, static per hex)*: how many zombies
this hex can hold, baked from real 1890s human population... Floor of 1,000."
decisions.md D3: "Capacity IS the difficulty curve, and that is the point" --
real history gates the map, so the Manchester -> London arc ramps because the
census says it does, with no hand-authored region locks.

--------------------------------------------------------------------------
Source order, and where it departs from D3
--------------------------------------------------------------------------
D3 orders the sources Wikidata -> OSM `place` tags -> a floor of 1,000, and
describes Wikidata as "good coverage for cities and towns". Measured before
this bake was written (the numbers are in fetch_wikidata_population.py's
docstring), that last part is wrong: Wikidata carries a dated 1891 population
for 378 items in the whole GB+Ireland bbox, most of them country- or
county-level aggregates, and it has NOTHING before 2010 for Manchester,
Liverpool, Leeds, Sheffield, Glasgow, Edinburgh, Bristol, Newcastle or
Nottingham.

The ORDER is kept; what changes is that the tiers below Wikidata now carry
almost all of the map:

  1. Wikidata census population, preferring 1891 and falling back to 1901 then
     1881, joined to an OSM place node by its `wikidata` tag. 202 settlements.
     A real 1891 figure always wins.
  2. The OSM `population` tag, scaled by ONE national factor (below). 2,296
     settlements -- every city, ~half the towns, ~7% of villages.
  3. The median tagged population of that place kind, scaled by the same
     factor. 37,900 settlements. This is the long tail: OSM knows a village is
     there (16,439 village nodes) far more often than it knows how big it is
     (1,158 tagged).
  4. Anywhere no settlement reaches, design_doc.md's floor of 1,000.

THE NATIONAL FACTOR exists because tiers 2 and 3 are modern population and the
game is set in January 1890. It is not a guess: it is whatever makes the total
match the 1891 census of the United Kingdom (37,802,400, Wikidata Q145 P1082 at
1891-01-01), after subtracting what tier 1 already contributes in real 1891
figures. Measured on the 2026-08-28 extracts it comes out at 0.5105, which is
independently close to the 80 settlements where a real 1891 figure and a modern
OSM tag are BOTH known -- their median modern/1891 ratio is 1.94, i.e. 0.515 the
other way round. The two numbers were derived from different data and agree to
1%, which is the evidence that the factor is a real historical ratio rather than
a fudge.

Accepted consequence, stated rather than buried: a town that grew or shrank
against the national trend is wrong by however much it diverged. Bexhill-on-Sea
is 8.3x its 1891 self and gets scaled as though it were 1.9x. Real 1891 figures
(tier 1) override exactly where Wikidata has them, and nowhere else.

--------------------------------------------------------------------------
Placing a settlement on the hex grid
--------------------------------------------------------------------------
A settlement is a POINT in OSM and an AREA on the ground, so its population is
spread over hexes with a Gaussian whose sigma comes from the area that many
people occupy at 5,000 people/km2 -- floored at half a hex, so a hamlet lands on
one hex and does not smear. Weights are computed over LAND hexes only and then
renormalised, so a coastal town's whole population lands ashore instead of
draining into the sea. Measured: without that renormalisation 2.86 million
people fell on ocean hexes and were lost.

THE THREE NAMED CITIES ARE PLACED BY NAME, NOT BY PROJECTION, and that is
deliberate. `geo_projection`'s affine fits real lon/lat to today's hex positions
with a 1,265-unit RMS residual (~2.5 hex radii) -- it is fit to 21 anchors, 18 of
which are hand-drawn region blobs, and they dominate the least squares. At
Manchester the residual is 1,201 units, which is 1.6 hex ROWS: projecting real
Manchester put 253,000 people on an empty moorland hex two rows north and left
the game's own four Manchester hexes -- the player's starting settlement -- with
84,000 between them. Using the correspondence the calibration table itself
already states (its `q, r` column IS "where this game puts this real place")
fixes the three cities that have a named footprint in BritishGeographyData;
everything else stays on the affine, which is the right answer for the other
40,000 settlements because the land-cover raster they have to agree with is
baked through that same affine.

Re-fitting the projection instead would move every baked product by up to 780
world units and is a `[design]` call, not a bake's decision -- see backlog.md.
"""

import argparse
import io
import json
import math
import os
import re
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from geo_projection import CALIBRATION_POINTS, HEX_SIZE, apply_affine, axial_to_world, fit_affine  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(HERE, "..", "..", "assets", "terrain_data")
OUTPUT_NAME = "zombie_population.zpop"
PLACES_CACHE = os.path.join(HERE, "cache", "places", "place_nodes.json")

## Same file bake_vector_landcover.land_chunks() parses, for the same reason:
## BritishGeographyData._LAND_RLE is the one source of truth for which hexes are
## land, and restating it as a Python literal would drift the first time the
## coastline is re-baked.
LAND_RLE_GD = os.path.join(HERE, "..", "..", "scripts", "world", "data", "BritishGeographyData.gd")

## Must match BritishGeographyData.MAP_BOUNDS (`Rect2i(0, 0, 154, 179)`) exactly.
## Stated as ORIGIN and SIZE, matching Rect2i, NOT as the (min, max) corner pair
## bake_landcover.py's own MAP_BOUNDS_Q/R happen to be -- the two spellings give
## the same span here only because the origin is 0. The .zpop header carries both
## numbers and ZombiePopulationData checks them, so a drift is a loud failure.
MAP_BOUNDS_ORIGIN = (0, 0)
MAP_BOUNDS_SIZE = (154, 179)

## design_doc.md 2.1: "Floor of 1,000, so even the emptiest hex in Britain holds
## 750 zombies at the Hive Core threshold."
POPULATION_FLOOR = 1000

## 1891 census of the United Kingdom (Wikidata Q145, P1082 at 1891-01-01), which
## at that date included all of Ireland -- the same territory this map covers.
## The whole point of the national factor is to land the bake's own total on this
## number, so it is stated once, here.
CENSUS_1891_UK = 37_802_400

## People per square kilometre used to turn a population into an urban FOOTPRINT.
## Not a density anyone measured: it is the conurbation-scale figure that makes
## the resulting radii match the game's own city footprints. At 5,000/km2 London
## spreads over ~17 hexes against the 12 BritishGeographyData gives Greater
## London, and Manchester over ~2 against its 4. The dense-core figure (the
## County of London held 5.57M in 303 km2 = 18,400/km2) would put all of London
## inside a single hex, which is geometrically true and useless as terrain.
URBAN_DENSITY_PER_KM2 = 5000.0

## HexCoord.WORLD_UNITS_PER_REAL_METER. Duplicated with the same "must match"
## contract as bake_landcover.WORLD_UNITS_PER_PIXEL.
WORLD_UNITS_PER_REAL_METER = 0.1025599

## Below this share of a settlement's peak weight a hex contributes nothing --
## it bounds the per-settlement footprint scan without a hard radius.
WEIGHT_EPSILON = 1e-4

## Which OSM settlement name is which row of geo_projection.CALIBRATION_POINTS.
## Only settlements with a named footprint in BritishGeographyData belong here;
## see this file's doc comment for why they bypass the affine.
NAMED_CITY_ANCHORS = {
    "Manchester": "Manchester",
    "Birmingham": "Birmingham",
    "London": "London (Tower of London)",
}

## Census years fetch_wikidata_population.py caches, best first. 1891 is the
## census the game's January 1890 sits between; 1901 and 1881 are equally far
## either side, and 1901 is listed first only because it has more rows.
CENSUS_PREFERENCE = (1891, 1901, 1881)

_MAGIC = b"ZPOP"
_FORMAT_VERSION = 1
_HEADER_SIZE = 32


def land_hexes() -> set:
    """Every (q, r) BritishGeographyData._LAND_RLE marks as land."""
    text = io.open(LAND_RLE_GD, encoding="utf-8").read()
    body = text.split("const _LAND_RLE: Array = [", 1)[1]
    land = set()
    for line in body.splitlines():
        if line.strip() == "]":
            break
        row = re.match(r"\s*\[(-?\d+),\s*\[(.*)\]\],?\s*", line)
        if not row:
            continue
        r = int(row.group(1))
        for lo, hi in re.findall(r"Vector2i\((-?\d+),\s*(-?\d+)\)", row.group(2)):
            for q in range(int(lo), int(hi) + 1):
                land.add((q, r))
    if not land:
        raise SystemExit(f"parsed no land hexes from {LAND_RLE_GD} -- has its format changed?")
    return land


def parse_population_tag(raw) -> int:
    """OSM `population` is free text. Take the leading number or nothing.

    Real values in these extracts include "12,345", "1 500", "8" and
    "3000 (2011)". Anything that does not start with a digit -- "~800",
    "unknown" -- is not guessed at; it falls through to the next source tier.
    """
    if not raw:
        return 0
    match = re.match(r"^\s*([\d][\d,. ]*)", raw)
    if not match:
        return 0
    try:
        value = int(float(match.group(1).replace(",", "").replace(" ", "")))
    except ValueError:
        return 0
    return value if value > 0 else 0


def world_to_axial_fractional(x: float, y: float) -> tuple:
    """Port of HexCoord.world_to_axial_fractional() (scripts/world/HexCoord.gd)."""
    q = (math.sqrt(3.0) / 3.0 * x - y / 3.0) / HEX_SIZE
    r = (2.0 / 3.0 * y) / HEX_SIZE
    return q, r


def load_census() -> dict:
    """{qid: population} preferring the census year nearest the game's 1890."""
    from fetch_wikidata_population import fetch_all
    by_year = fetch_all()
    census = {}
    for year in reversed(CENSUS_PREFERENCE):  # best year written last, so it wins
        for qid, population in by_year.get(year, {}).items():
            census[qid] = population
    return census


def resolve_settlements(places: list, census: dict) -> tuple:
    """Attach one population and a source tier to every usable place node.

    Returns (settlements, national_factor, stats). `settlements` entries are
    (place, population, tier) where population is still in its SOURCE era --
    tier 1 is already 1891, tiers 2 and 3 are modern and get scaled by
    national_factor at distribution time.
    """
    tagged = {}
    for place in places:
        value = parse_population_tag(place["population"])
        if value:
            tagged.setdefault(place["place"], []).append(value)
    kind_median = {}
    for kind, values in tagged.items():
        values.sort()
        kind_median[kind] = values[len(values) // 2]

    settlements = []
    stats = {"wikidata": 0, "osm": 0, "kind": 0, "unusable": 0}
    for place in places:
        qid = place["wikidata"]
        if qid and qid in census:
            settlements.append((place, census[qid], "wikidata"))
            stats["wikidata"] += 1
            continue
        value = parse_population_tag(place["population"])
        if value:
            settlements.append((place, value, "osm"))
            stats["osm"] += 1
            continue
        median = kind_median.get(place["place"])
        if median:
            settlements.append((place, median, "kind"))
            stats["kind"] += 1
        else:
            stats["unusable"] += 1

    census_total = sum(p for _, p, tier in settlements if tier == "wikidata")
    modern_total = sum(p for _, p, tier in settlements if tier != "wikidata")
    if modern_total <= 0:
        raise SystemExit("no modern population to scale -- is cache/places/place_nodes.json empty?")
    national_factor = (CENSUS_1891_UK - census_total) / modern_total
    stats["kind_median"] = kind_median
    stats["census_total"] = census_total
    stats["modern_total"] = modern_total
    return settlements, national_factor, stats


def distribute(settlements: list, national_factor: float, land: set) -> dict:
    """Spread every settlement's population over land hexes. {(q, r): float}."""
    transform = fit_affine(CALIBRATION_POINTS)
    calibration_hex = {name: (q, r) for name, _lon, _lat, q, r in CALIBRATION_POINTS}

    capacity = {}
    anchored = 0
    for place, raw_population, tier in settlements:
        population = raw_population if tier == "wikidata" else raw_population * national_factor

        anchor_row = NAMED_CITY_ANCHORS.get(place["name"]) if place["place"] == "city" else None
        if anchor_row and anchor_row in calibration_hex:
            centre_x, centre_y = axial_to_world(*calibration_hex[anchor_row])
            anchored += 1
        else:
            centre_x, centre_y = apply_affine(transform, place["lon"], place["lat"])

        radius_m = math.sqrt((population / URBAN_DENSITY_PER_KM2) / math.pi) * 1000.0
        sigma = max(radius_m * WORLD_UNITS_PER_REAL_METER, HEX_SIZE * 0.5)

        frac_q, frac_r = world_to_axial_fractional(centre_x, centre_y)
        base_q, base_r = int(round(frac_q)), int(round(frac_r))

        # Grow the scan until it finds land. A settlement whose projected point
        # lands in the sea (an island, an estuary town, or the projection's own
        # residual) still has to come ashore somewhere.
        weights = {}
        reach = max(1, int(math.ceil(2.0 * sigma / (HEX_SIZE * 1.5))))
        while True:
            for dq in range(-reach, reach + 1):
                for dr in range(-reach, reach + 1):
                    hex_coord = (base_q + dq, base_r + dr)
                    if hex_coord not in land:
                        continue
                    hex_x, hex_y = axial_to_world(*hex_coord)
                    distance_sq = (hex_x - centre_x) ** 2 + (hex_y - centre_y) ** 2
                    weight = math.exp(-distance_sq / (sigma * sigma))
                    if weight > WEIGHT_EPSILON:
                        weights[hex_coord] = weight
            if weights or reach > 8:
                break
            reach += 2

        total_weight = sum(weights.values())
        if total_weight <= 0.0:
            continue  # nowhere within 8 hexes is land; this settlement is off-map
        for hex_coord, weight in weights.items():
            capacity[hex_coord] = capacity.get(hex_coord, 0.0) + population * weight / total_weight

    print(f"  placed {anchored} named cities on their calibration-table hex, "
          f"{len(settlements) - anchored:,} by projection")
    return capacity


def encode(capacity: dict, land: set) -> bytes:
    """Pack the whole MAP_BOUNDS rectangle. See ZombiePopulationData.gd.

      off  size  type     field
        0     4  bytes    magic "ZPOP"
        4     2  uint16   format version (= 1)
        6     2  uint16   reserved (= 0)
        8     4  int32    q0  -- MAP_BOUNDS.position.x
       12     4  int32    r0  -- MAP_BOUNDS.position.y
       16     4  uint32   width  -- MAP_BOUNDS.size.x
       20     4  uint32   height -- MAP_BOUNDS.size.y
       24     4  uint32   floor  -- POPULATION_FLOOR, so the reader states the
                                    floor from the data rather than a second
                                    copy of the constant
       28     4  uint32   reserved (= 0)
       32        width*height*4  uint32 capacity, r-major then q

    Sea hexes are 0, which is why 0 and "1,000" have to stay distinguishable:
    0 means "no zombies can be here at all", the floor means "the emptiest
    inhabited hex in Britain".
    """
    q0, r0 = MAP_BOUNDS_ORIGIN
    width, height = MAP_BOUNDS_SIZE
    out = bytearray(struct.pack("<4sHHiiIIII", _MAGIC, _FORMAT_VERSION, 0,
                                q0, r0, width, height, POPULATION_FLOOR, 0))
    values = bytearray(width * height * 4)
    for r in range(r0, r0 + height):
        row_base = (r - r0) * width * 4
        for q in range(q0, q0 + width):
            hex_coord = (q, r)
            if hex_coord not in land:
                continue
            value = max(POPULATION_FLOOR, int(round(capacity.get(hex_coord, 0.0))))
            struct.pack_into("<I", values, row_base + (q - q0) * 4, value)
    out += values
    return bytes(out)


def bake(out_dir: str = OUTPUT_DIR) -> str:
    started = time.time()

    print("=== Step 1: land mask ===")
    land = land_hexes()
    print(f"  {len(land):,} land hexes of {MAP_BOUNDS_SIZE[0] * MAP_BOUNDS_SIZE[1]:,} in MAP_BOUNDS")

    print("=== Step 2: OSM place nodes ===")
    if not os.path.exists(PLACES_CACHE):
        raise SystemExit(f"missing {PLACES_CACHE}\n"
                         "  run: python tools/geo_bake/extract_place_nodes.py")
    with io.open(PLACES_CACHE, encoding="utf-8") as f:
        places = json.load(f)
    print(f"  {len(places):,} settlement nodes")

    print("=== Step 3: Wikidata census population ===")
    census = load_census()
    print(f"  {len(census):,} items with a census-year population")

    print("=== Step 4: resolve one population per settlement ===")
    settlements, national_factor, stats = resolve_settlements(places, census)
    print(f"  per-kind median (modern, from the tagged subset): {stats['kind_median']}")
    print(f"  tier 1 wikidata 1891: {stats['wikidata']:,} settlements, {stats['census_total']:,.0f} people")
    print(f"  tier 2 osm tag:       {stats['osm']:,} settlements")
    print(f"  tier 3 kind median:   {stats['kind']:,} settlements")
    print(f"  unusable:             {stats['unusable']:,}")
    print(f"  modern subtotal {stats['modern_total']:,.0f} -> national factor {national_factor:.4f} "
          f"(to reach the 1891 census total of {CENSUS_1891_UK:,})")

    print("=== Step 5: distribute onto hexes ===")
    capacity = distribute(settlements, national_factor, land)

    print("=== Step 6: write ===")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, OUTPUT_NAME)
    with open(path, "wb") as f:
        f.write(encode(capacity, land))
    print(f"  wrote {path} ({os.path.getsize(path):,} bytes)")

    print("=== Summary ===")
    final = {}
    for hex_coord in land:
        final[hex_coord] = max(POPULATION_FLOOR, int(round(capacity.get(hex_coord, 0.0))))
    total = sum(final.values())
    above_floor = sum(1 for v in final.values() if v > POPULATION_FLOOR)
    print(f"  total capacity over land: {total:,} "
          f"({100.0 * total / CENSUS_1891_UK:.1f}% of the 1891 census)")
    print(f"  hexes above the floor: {above_floor:,} / {len(final):,}")
    ranked = sorted(final.items(), key=lambda kv: -kv[1])
    print("  ten largest hexes: " + ", ".join(f"({q},{r})={v:,}" for (q, r), v in ranked[:10]))
    print(f"  total time {time.time() - started:.0f}s")
    return path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default=OUTPUT_DIR)
    args = parser.parse_args()
    bake(args.out_dir)
