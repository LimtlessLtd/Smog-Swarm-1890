class_name SubHexTerrainOverride
extends RefCounted

## The sub-hex terrain WRITE path SubHexTerrainQuery's own doc comment
## anticipated ("A sparse mutation store ... lands with whichever later
## phase first needs to actually change a sub-cell"). Town Hall founding is
## that first consumer: a founded settlement paves a growing disc of its hex
## URBAN, and every existing sub-hex reader has to see it.
##
## Sparse by disc, not by sub-cell. A founded hex stores one center+radius
## pair, not up to SUB_HEX_GRID_N^2 (110,889) per-cell entries — the urban
## extent is a circle by construction (SettlementFoundingController grows one
## radius with population), so storing the circle is both smaller and the
## only representation that can grow without rewriting every cell it already
## covers. Same "store the rule, not the expansion" restraint
## SubHexPortalGraph takes with portals.
##
## Read path: SubHexTerrainQuery.sample() consults this AFTER its own cache
## lookup and returns a duplicated dictionary when an override hits, so the
## raw baked-raster cache is never poisoned by a mutation that can move.
## That single consult point is why all four existing sub-hex readers
## (BuildingManager placement legality, SubHexPortalGraph passability,
## SubHexSoilQuery, SubHexGroundView's rendered ground) pick this up without
## each needing their own override branch.
##
## Deliberately NOT gated on baked-corridor coverage: an override applies
## whether or not RealTerrainSampler has real data under it, since a Town
## Hall can be founded well outside the baked corridor and still has to
## read URBAN there. See SubHexTerrainQuery.biome_at() for how that composes
## with the macro-hex fallback.
##
## Pure data — no signal of its own. "This hex's urban extent changed" is a
## domain event SettlementFoundingController owns and emits
## (urban_extent_changed); a static store emitting gameplay signals would be
## a second responsibility here and a static-signal workaround in a language
## that has none.
##
## No persistence of its own either — SettlementFoundingController rebuilds
## every disc from the restored BuildingInstance set on load (see that
## class's rebuild_from_buildings()), so this store is always derived state,
## never a save-file authority. That's what keeps it from repeating
## ReclamationManager._drained_hexes's need for its own save entry.

## Vector2i (macro hex) -> {center: Vector2 (world), radius: float (world units)}.
## One entry per founded hex; absent means "no override, read the raster".
static var _urban_discs: Dictionary = {}

## Registers (or resizes) `hex_coord`'s urban disc, centered on world
## position `center` with `radius` in world units. Returns true only if the
## stored disc actually moved, so a per-day population recompute that didn't
## shift the boundary doesn't make the caller re-emit or repaint.
static func set_urban_disc(hex_coord: Vector2i, center: Vector2, radius: float) -> bool:
	var existing: Dictionary = _urban_discs.get(hex_coord, {})
	if not existing.is_empty() and is_equal_approx(existing["radius"], radius) and existing["center"].is_equal_approx(center):
		return false
	_urban_discs[hex_coord] = {"center": center, "radius": radius}
	return true

## Removes `hex_coord`'s disc entirely — the hex reverts to its raw baked
## terrain. Used when a founded settlement's Town Hall is ruined/demolished
## (SettlementFoundingController), not exposed as a general terrain eraser.
## Returns true only if a disc was actually there to remove.
static func clear_urban_disc(hex_coord: Vector2i) -> bool:
	return _urban_discs.erase(hex_coord)

## Current urban radius (world units) for `hex_coord`, or 0.0 if that hex was
## never founded. Lets a caller size a redraw/effect to the real extent
## instead of assuming a whole hex is paved.
static func get_urban_radius(hex_coord: Vector2i) -> float:
	var disc: Dictionary = _urban_discs.get(hex_coord, {})
	return disc.get("radius", 0.0)

static func has_urban_disc(hex_coord: Vector2i) -> bool:
	return _urban_discs.has(hex_coord)

static func get_founded_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_urban_discs.keys())
	return result

## True if `world_pos` falls inside `hex_coord`'s urban disc. Squared-distance
## compare — this runs per sub-cell across SubHexGroundView's whole render
## grid, so the sqrt in Vector2.distance_to() is worth skipping.
static func is_urban_at(hex_coord: Vector2i, world_pos: Vector2) -> bool:
	var disc: Dictionary = _urban_discs.get(hex_coord, {})
	if disc.is_empty():
		return false
	var radius: float = disc["radius"]
	return world_pos.distance_squared_to(disc["center"]) <= radius * radius

## Clears every disc. SettlementFoundingController.rebuild_from_buildings()
## calls this before restoring the set a save actually contained, so a load
## never inherits the previous session's founded hexes — the same
## clear-then-restore contract BuildingManager.load_save_entries() follows.
static func clear_all() -> void:
	_urban_discs.clear()
