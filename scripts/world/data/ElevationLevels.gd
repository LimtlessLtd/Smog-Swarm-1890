class_name ElevationLevels
extends RefCounted

## design_doc.md §5's "Logical Elevation System" — the discrete `height_level`
## 0-4 band a continuous `HexCell.elevation` falls in, plus the presentation
## each band gets. Static, stateless, no scene-tree presence, same shape as
## HexCoord/HexPathfinder: a rule about a value, not an owner of one.
##
## DERIVED, never stored. HexCell.elevation already holds the real
## AWS/Mapzen metres (RealTerrainSampler, normalised against
## ELEVATION_METRES_AT_SCALE_TOP), so a second `height_level` field on
## HexCell would be a cached copy of a pure function of a field sitting
## right next to it — the same "adds nothing to the save file" reasoning
## UnitUpgrades.gd already applies to per-unit tech bonuses. Every consumer
## (passability, the relief overlay, and whatever picks up §5's vision/LoS/
## range modifiers later) calls level_for() instead of reading a field that
## could drift from the elevation beside it.
##
## Bands are cut in REAL METRES, not in normalised 0..1 units, so they mean
## something a player can check against a map of Britain and do not silently
## re-scale if ELEVATION_METRES_AT_SCALE_TOP is ever re-fitted.

const SEA_LEVEL: int = 0
const LOWLAND: int = 1
const HILL: int = 2
const HIGHLAND: int = 3
const MOUNTAIN: int = 4

## Upper bound (exclusive) in real metres for LOWLAND, HILL and HIGHLAND in
## that order; anything at or above the last entry is MOUNTAIN. Chosen
## against real British topography rather than by splitting the range
## evenly: 100 m is roughly where the lowland plain gives out, 300 m is
## moorland/fell shoulder, and 600 m is the band that holds the Pennine,
## Lakeland, Snowdonian and Highland summits and very little else.
##
## Balancing numbers. They decide how much of the map MOUNTAIN makes
## impassable, so changing them changes routes — scripts/test/verify_elevation.gd
## re-measures the resulting level histogram and, more importantly, whether
## the landmass stays connected.
const _METRE_THRESHOLDS: Array[float] = [100.0, 300.0, 600.0]

## `is_ocean` forces SEA_LEVEL regardless of the sampled elevation —
## design_doc.md §5: "sea level should be applied everywhere the sea biome
## is present". Without it a coastal ocean hex whose 5x5 elevation sample
## caught some neighbouring shoreline reads as LOWLAND, which would make
## the sea render as land in the relief overlay.
static func level_for(elevation: float, is_ocean: bool) -> int:
	if is_ocean:
		return SEA_LEVEL
	var metres := to_metres(elevation)
	for i in _METRE_THRESHOLDS.size():
		if metres < _METRE_THRESHOLDS[i]:
			return LOWLAND + i
	return MOUNTAIN

## The lowest normalised elevation that still reads as MOUNTAIN — the exact
## value the impassability rule turns on. Exposed so MountainPassCarver can
## carve to just under it without hardcoding a copy of the threshold, which
## is how a pass ends up either still impassable or needlessly flattened.
static func mountain_threshold_elevation() -> float:
	return _METRE_THRESHOLDS[_METRE_THRESHOLDS.size() - 1] / RealTerrainSampler.ELEVATION_METRES_AT_SCALE_TOP

static func of_cell(cell: HexCell) -> int:
	if not cell:
		return SEA_LEVEL
	return level_for(cell.elevation, cell.biome_type == GameEnums.BiomeType.OCEAN)

## HexCell.elevation's own documented scale (0.0 sea level .. 1.0 highest
## Pennine peaks) resolved back to the metres it was normalised from —
## RealTerrainSampler owns that constant, this does not redeclare it.
static func to_metres(elevation: float) -> float:
	return elevation * RealTerrainSampler.ELEVATION_METRES_AT_SCALE_TOP

## design_doc.md §5 Level 4: "IMPASSABLE for all ground units, vehicles, and
## zombies." Read by HexCell.is_passable(), so it applies to pathfinding,
## horde flow fields and building placement through the one check they all
## already share, rather than each growing its own elevation clause.
static func is_impassable(level: int) -> bool:
	return level == MOUNTAIN

static func display_name(level: int) -> String:
	match level:
		SEA_LEVEL:
			return "Sea Level"
		LOWLAND:
			return "Lowland"
		HILL:
			return "Hill"
		HIGHLAND:
			return "Highland"
		MOUNTAIN:
			return "Mountain"
		_:
			return "Unknown"

## No presentation lives here any more. This class carried a per-band
## relief_tint()/contour_color()/contour_width() set for the first version of
## ElevationReliefView, which shaded whole hexes by BAND and drew contours
## along hex edges. Both were replaced by a slope-derived hillshade at raster
## resolution (ReliefImageBuilder) after "i still cannot clearly see elevation
## in the tactical view. things need to actually look as though they are
## higher/lower in elevation than their neighbours" (user report) — a band
## tint shades a plateau and the cliff below it identically, and a hex-edge
## contour draws a slope that follows hex geometry rather than terrain.
## Nothing reads a band for display now; the bands remain purely as the
## passability rule (is_impassable()) and as a name for a height
## (display_name()).
