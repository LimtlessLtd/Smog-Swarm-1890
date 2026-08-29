class_name DataAttribution
extends RefCounted

## The third-party geographic data credits this game is REQUIRED to display,
## in one place so every surface that shows them shows the same text.
##
## This is a licensing obligation, not polish. `tools/geo_bake/`'s
## `fetch_overpass.py` flagged it in its own docstring and deferred it while
## OpenStreetMap data was only feeding offline rasters; the Real-Geography
## Vector Terrain epic made OSM geometry the thing the game actually RENDERS
## as terrain, which raises it from a nicety to a real condition of use.
##
## OpenStreetMap is licensed ODbL 1.0, whose §4.3 requires any Produced Work
## to carry a notice that it uses OSM data and names the licence — the
## community's canonical wording for that is "© OpenStreetMap contributors",
## which is why that string is reproduced verbatim rather than paraphrased.
##
## Natural Earth (the coastline/landmass source, `coastline.py`) is explicitly
## public domain and requires no credit at all; it is listed anyway because a
## credits block that names only the sources that can sue is a worse credits
## block, and because knowing where the coastline came from is genuinely
## useful to anyone reading the bake tools.
##
## Terrain elevation comes from the Mapzen Terrain Tiles dataset hosted on
## AWS Open Data (`fetch_terrarium.py` / `terrarium_mosaic.py`), which is
## itself a composite of public-domain national datasets and asks that the
## underlying providers be acknowledged.
##
## Wikidata (`fetch_wikidata_population.py`) supplies the real 1881/1891/1901
## census figures behind `total_zombie_pop`. It is CC0 and legally needs no
## credit, and is listed for the same reason Natural Earth is — the population
## of a hex is a number a player might reasonably want to trace to a source.
##
## Kept as plain text with no markup so it can be dropped into a Label, a
## RichTextLabel, or a future Steam store page without re-authoring.

## One-line form, for a boot-screen footer where vertical space is scarce.
## Carries the ODbL credit in full because that is the part with a legal
## requirement attached — the other three sources compress to their names.
const SHORT_NOTICE: String = "Map data © OpenStreetMap contributors (ODbL 1.0) · Coastlines from Natural Earth · Elevation from Mapzen Terrain Tiles · Historical population from Wikidata (CC0)"

## Full form, for a credits screen. Each entry states the dataset, what it is
## used for in this game, and its licence, so the notice is auditable rather
## than decorative.
const FULL_NOTICE: String = """Geographic data sources

OpenStreetMap — land cover, woodland, farmland, urban and industrial areas, rivers, lakes and canals, and the settlement points that carry each hex's population capacity.
Map data © OpenStreetMap contributors, available under the Open Database Licence (ODbL) 1.0.
https://www.openstreetmap.org/copyright

Natural Earth — the coastline and landmass boundary of Great Britain and Ireland.
Public domain, made with Natural Earth.
https://www.naturalearthdata.com

Mapzen Terrain Tiles (AWS Open Data) — terrain elevation and hillshade relief.
Compiled from public-domain national elevation datasets.
https://registry.opendata.aws/terrain-tiles/

Wikidata — 1881/1891/1901 census populations, which set how many zombies each region can hold.
Released to the public domain under CC0 1.0.
https://www.wikidata.org"""
