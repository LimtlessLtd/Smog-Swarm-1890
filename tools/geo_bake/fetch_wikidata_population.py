"""Wikidata (CC0) historical population statements for the GB+Ireland bbox,
cached one JSON file per census year.

    python tools/geo_bake/fetch_wikidata_population.py

design_doc.md 2.1 and decisions.md D3 put Wikidata FIRST in the capacity source
order, described as "good coverage for cities and towns". **Measured 2026-08-28,
that is not true**, and the numbers are recorded here so the next reader does not
re-derive them:

  items in the GB+Ireland bbox with a P1082 population dated to a census year
    1871: 280   1881: 377   1891: 378   1901: 407   1911: 452   (474 distinct)

  of those 378 rows for 1891, the largest are aggregates, not settlements:
    United Kingdom 37,802,400 | London 5,565,856 | Wales 1,771,451 |
    Birmingham 478,000 | Aberdeen 121,623 | County Offaly 65,563 | ...

  Manchester, Liverpool, Leeds, Sheffield, Glasgow, Edinburgh, Bristol,
  Newcastle and Nottingham have NO population statement before 2010 at all
  (checked directly: wd:Q18125 p:P1082 returns 2011/2014/2017/2018 only).

  the settlement-level rows are dominated by one bulk import: the Isle of Ely /
  Cambridgeshire parishes. Ely, March, Whittlesey, Chatteris, Littleport,
  Soham, Swavesey, Over, Balsham and Whittlesford are all present; almost no
  comparable Lancashire or Yorkshire village is.

  the bbox also catches a few places that are not in Britain at all -- Dieppe
  (lon 1.075, lat 49.925) sits inside its south-east corner.

So this fetcher is real and worth having -- 202 of its rows join to an OSM place
node by QID, including London and Birmingham, and a real 1891 figure beats a
scaled modern one every time -- but it covers a low single-digit percentage of
inhabited places, and bake_population.py has to carry the rest. See that file's
"Source order" section.

QUERY SHAPE MATTERS. The obvious query (`?item wdt:P17 wd:Q145` joined to a date
RANGE filter) returns 502/504 from query.wikidata.org every time; so does
`SERVICE wikibase:box` joined to the same. What answers in ~5 s is pinning the
qualifier to ONE exact date literal and filtering coordinates arithmetically:
`?st pq:P585 "1891-01-01T00:00:00Z"^^xsd:dateTime` plus geof:latitude/longitude
bounds. Hence one request per census year rather than one for the range.

Cached under cache/wikidata/ (gitignored, like every other bake cache). Delete
the directory to re-fetch.
"""

import argparse
import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

_CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache", "wikidata")
_ENDPOINT = "https://query.wikidata.org/sparql"

## The Wikimedia Foundation's user-agent policy requires a descriptive agent
## with contact details on automated queries; an anonymous one is throttled or
## refused outright.
_USER_AGENT = ("SmogSwarm1890-geobake/1.0 "
               "(https://github.com/LimtlessLtd/Smog-Swarm-1890)")

## UK censuses either side of the game's own January 1890. 1891 is the one the
## bake prefers; the others exist so a settlement recorded in only one of them
## still contributes (bake_population.py picks the nearest to 1891).
CENSUS_YEARS = (1881, 1891, 1901)

## BritishGeographyData's map covers GB + Ireland with an ocean margin. Slightly
## wider than the landmass so a coastal settlement whose coordinate sits just
## outside is still returned; bake_population.py drops anything that projects
## into a sea hex anyway.
_BBOX = (-11.0, 49.5, 2.2, 61.0)  # min_lon, min_lat, max_lon, max_lat

_QUERY = """SELECT ?item ?itemLabel ?pop ?coord WHERE {{
  ?item p:P1082 ?st .
  ?st ps:P1082 ?pop .
  ?st pq:P585 "{year}-01-01T00:00:00Z"^^xsd:dateTime .
  ?item wdt:P625 ?coord .
  FILTER(geof:latitude(?coord) > {min_lat} && geof:latitude(?coord) < {max_lat} &&
         geof:longitude(?coord) > {min_lon} && geof:longitude(?coord) < {max_lon})
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}"""


def _cache_path(year: int) -> str:
    return os.path.join(_CACHE_DIR, f"population_{year}.json")


def fetch_year(year: int, force: bool = False) -> list:
    """Rows for one census year as [{qid, label, population, lon, lat}, ...]."""
    path = _cache_path(year)
    if os.path.exists(path) and not force:
        with io.open(path, encoding="utf-8") as f:
            return json.load(f)

    min_lon, min_lat, max_lon, max_lat = _BBOX
    query = _QUERY.format(year=year, min_lon=min_lon, min_lat=min_lat,
                          max_lon=max_lon, max_lat=max_lat)
    url = _ENDPOINT + "?" + urllib.parse.urlencode({"query": query, "format": "json"})
    request = urllib.request.Request(url, headers={
        "Accept": "application/sparql-results+json",
        "User-Agent": _USER_AGENT,
    })
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = json.loads(response.read().decode("utf-8"))

    rows = []
    for binding in payload["results"]["bindings"]:
        # "Point(-2.2446 53.484)" -- WKT is lon-then-lat, the opposite order to
        # every other coordinate pair in this pipeline.
        point = binding["coord"]["value"]
        lon, lat = point[point.index("(") + 1:point.index(")")].split()
        rows.append({
            "qid": binding["item"]["value"].rsplit("/", 1)[-1],
            "label": binding.get("itemLabel", {}).get("value", ""),
            "population": float(binding["pop"]["value"]),
            "lon": float(lon),
            "lat": float(lat),
        })

    os.makedirs(_CACHE_DIR, exist_ok=True)
    with io.open(path, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False)
    return rows


def fetch_all(force: bool = False) -> dict:
    """{year: {qid: population}} for every census year in CENSUS_YEARS."""
    out = {}
    for year in CENSUS_YEARS:
        cached = os.path.exists(_cache_path(year)) and not force
        try:
            rows = fetch_year(year, force=force)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            # A bake that silently loses its best source is worse than one that
            # stops: the map would look baked and be wrong. Caller decides.
            raise SystemExit(f"Wikidata query for {year} failed: {exc}") from exc
        out[year] = {row["qid"]: row["population"] for row in rows}
        print(f"  {year}: {len(rows):,} rows{' (cached)' if cached else ''}", flush=True)
        if not cached:
            time.sleep(1.0)  # courtesy delay on a shared public endpoint
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="re-fetch even if cached")
    args = parser.parse_args()
    print("=== Wikidata historical population (CC0) ===")
    years = fetch_all(force=args.force)
    every = set()
    for qids in years.values():
        every |= set(qids)
    print(f"\n{len(every):,} distinct items across {len(years)} census years")
