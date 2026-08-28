class_name SubHexTerrainQuery
extends RefCounted

## Sparse, cached, on-demand sub-hex terrain lookup — Sub-Hex Mechanical
## Layer Phase 1a (todo.md, [[sub-hex-mechanical-layer-epic]] memory).
## Reuses RealTerrainSampler.sample_at_hex() (today's existing raster
## data, unchanged — the same fine-tile-preferring lookup sample_grid()
## already does per hex) at HexCoord's 30m sub-cell addressing instead of a dense
## per-cell object grid — 99%+ of sub-cells are never mutated by gameplay,
## so there's nothing to persist yet; this answers "what's the terrain at
## sub-cell X" the same way RealTerrainSampler already answers "what's the
## terrain at this exact world position," just cached per sub-cell address
## so repeated nearby queries (the expected access pattern once a real
## mechanic reads this) don't re-hit the raster every call.
##
## Phase 1a baseline: multiple adjacent 30m sub-cells aliased to the same
## underlying ~104m-pixel fine-tile value (where a fine tile was baked) or
## ~878m-pixel coarse value (elsewhere). Phase 1b rebaked fine tiles at
## FINE_TILE_PIXELS=333 (RealTerrainSampler.gd), one pixel per 30m sub-cell
## exactly (HexCoord.SUB_HEX_GRID_N) — a hex WITH a baked fine tile now has
## genuine per-sub-cell fidelity, not an alias. A hex without one yet still
## falls back to the ~878m-pixel coarse raster (aliased) until baked.
##
## Returns exactly RealTerrainSampler.sample_at()'s own shape
## (biome_type/terrain_feature/elevation_m/elevation, or {} off the baked
## corridor) — deliberately NOT soil_fertility, which sample_at() doesn't
## provide: HexMapGenerator derives that separately per MACRO-hex (a
## biome_type match plus a seeded noise pass, _apply_soil_noise()), not
## something this class can honestly answer at sub-hex resolution without
## inventing new derivation logic. That's Phase 3's job (extraction),
## when a real consumer needs it, not invented speculatively here.
##
## No write/mutation path of its own — the anticipated sparse mutation store
## arrived as SubHexTerrainOverride (Town Hall founding, its first real
## consumer). Every lookup here consults it, so all four sub-hex readers
## (BuildingManager placement legality, SubHexPortalGraph passability,
## SubHexSoilQuery, and the since-removed square per-hex ground) see a
## mutation without their own override branch. Overrides are applied to a DUPLICATE of the cached
## sample, never in place — _cache holds raw baked-raster data only, so a
## disc that later grows or is cleared can't leave a stale paved sub-cell
## behind.

static var _cache: Dictionary = {}  # "<hex.x>_<hex.y>_<sub.x>_<sub.y>" -> Dictionary (RealTerrainSampler.sample_at()'s own shape, {} cached too so a miss isn't re-queried every call)

## Terrain at sub-cell `sub_index` within macro-hex `hex_coord`.
static func sample(hex_coord: Vector2i, sub_index: Vector2i) -> Dictionary:
	var key := "%d_%d_%d_%d" % [hex_coord.x, hex_coord.y, sub_index.x, sub_index.y]
	var base: Dictionary
	if _cache.has(key):
		base = _cache[key]
	else:
		var sampled_pos := HexCoord.sub_hex_to_world(hex_coord, sub_index)
		base = RealTerrainSampler.sample_at_hex(hex_coord, sampled_pos)  # Prefers the fine per-hex tile when one's baked, same as sample_grid() already does — a plain sample_at() would silently lose that fidelity near the starting settlement.
		_cache[key] = base
	if not SubHexTerrainOverride.has_urban_disc(hex_coord):
		return base  # Overwhelmingly the common case — one dictionary lookup, and the cached result is returned by reference exactly as before overrides existed.
	return _with_urban_override(hex_coord, HexCoord.sub_hex_to_world(hex_coord, sub_index), base)

## Elevation in metres at one sub-cell, at the 30 m resolution the mechanical
## layer actually works in. This is the sanctioned sub-hex elevation read
## (CLAUDE.md section 3); sample()'s "elevation_m" is NOT the same number.
##
## Falls back to that coarse value for any hex with no baked elevation tile,
## which is every hex outside the baked corridor.
##
## ## Why sample()["elevation_m"] is deliberately left coarse
##
## It would be one line to point RealTerrainSampler._sample_fine() at the fine
## tiles and have every existing reader get 30 m elevation for free. That line
## would also silently regenerate the map.
##
## RealTerrainSampler.majority_biome() takes the MAXIMUM elevation of a 5x5 grid
## per hex, and its own comment records why that is safe today and exactly when
## it stops being: the coarse raster holds 4x4 blocks of identical values, so the
## max is "some substantial upland part of this hex is above the line" rather
## than a point maximum. At 30 m resolution it becomes a true point maximum, one
## summit starts classifying a whole 25-square-mile hex as Level 4, and that
## feeds MountainPassCarver and every passability decision downstream.
##
## Changing which hexes are mountains is a map-generation change and its own
## piece of work — see backlog.md. It is not a side effect the bake gets to have.
static func elevation_metres(hex_coord: Vector2i, sub_index: Vector2i) -> float:
	var fine: Variant = FineElevationTiles.metres_at(
		hex_coord, HexCoord.sub_hex_to_world(hex_coord, sub_index))
	if fine != null:
		return fine
	return float(sample(hex_coord, sub_index).get("elevation_m", 0.0))

## Applies a founded settlement's urban disc to one raw baked sample.
## Returns `base` itself (not a copy) whenever the override doesn't apply, so
## the no-op path allocates nothing.
##
## Two things a paved disc deliberately does NOT overwrite:
##
## - OCEAN/WATERWAY sub-cells. A town doesn't fill in the sea or culvert the
##   river it was built on. This is load-bearing, not cosmetic: WATERWAY is
##   impassable-without-a-Bridge (HexPathfinder.is_water_crossing_blocked()),
##   so letting an urban disc repaint a river would silently reopen exactly
##   the crossings that rule exists to close.
## - terrain_feature. A MARSH/PEAT_BOG strip inside the town stays marsh and
##   stays impassable until actually drained — ReclamationManager owns
##   draining as a resource-costed player action, and clearing the feature
##   here would hand that out free with a Town Hall.
static func _with_urban_override(hex_coord: Vector2i, world_pos: Vector2, base: Dictionary) -> Dictionary:
	if not SubHexTerrainOverride.is_urban_at(hex_coord, world_pos):
		return base
	var biome: GameEnums.BiomeType = base.get("biome_type", GameEnums.BiomeType.MOORLAND)
	if base.has("biome_type") and (biome == GameEnums.BiomeType.OCEAN or biome == GameEnums.BiomeType.WATERWAY):
		return base
	var result := base.duplicate()
	result["biome_type"] = GameEnums.BiomeType.URBAN
	return result

## Convenience wrapper — resolves `world_pos` to its own sub-cell first
## (HexCoord.world_to_sub_hex(), which independently re-derives which hex
## `world_pos` belongs to), then samples it. Two world positions inside the
## same 30m cell return the identical cached result. NOT what a caller
## iterating a grid already centered on one known hex wants — see
## sample_at_world_within() below.
static func sample_at_world(world_pos: Vector2) -> Dictionary:
	var addr := HexCoord.world_to_sub_hex(world_pos)
	return sample(addr["hex_coord"], addr["sub_index"])

## Same idea, but `hex_coord` is supplied, not re-derived from `world_pos` —
## for a caller iterating a sample grid explicitly centered on one hex
## (SubHexSoilQuery, and formerly the square ground's render grid) where a
## position near the grid's own edge/corner may geometrically overhang into
## a neighboring hex
## (HexCoord.SUB_HEX_GRID_SPAN's own doc comment) but must still resolve
## against THIS hex, not silently drift to that neighbor's data.
static func sample_at_world_within(hex_coord: Vector2i, world_pos: Vector2) -> Dictionary:
	return sample(hex_coord, HexCoord.sub_hex_index_within(hex_coord, world_pos))

## Clears the cache — only meaningful for tests/tooling; the underlying
## bake data is static for the lifetime of a running game, so production
## code never needs this. Mirrors no existing precedent 1:1, but avoids the
## cache silently becoming impossible to reset if a future phase (or a
## test) ever needs a clean slate.
static func clear_cache() -> void:
	_cache.clear()

## Live entry count — the cache is unbounded and static, so a caller that
## fans out over many sub-cells (SubHexPortalGraph walking whole hex edges)
## needs a way to measure what it strands here. Tests/tooling only.
static func cache_size() -> int:
	return _cache.size()

## Sub-cell passability at `world_pos` resolved against `hex_coord`
## specifically (sample_at_world_within() — locks to THIS hex, doesn't
## re-derive which hex world_pos geometrically belongs to). Reapplies
## HexCell.is_passable()'s exact MARSH/PEAT_BOG/OCEAN rule at sub-hex
## granularity; returns `fallback` when this position has no baked data
## (outside the corridor). Public — shared by SubHexPortalGraph (Phase 1c)
## and BuildingManager.get_placement_error() (Phase 3b) rather than each
## reimplementing the same rule.
static func is_passable_at(hex_coord: Vector2i, world_pos: Vector2, fallback: bool) -> bool:
	var sample := sample_at_world_within(hex_coord, world_pos)
	if sample.is_empty():
		return fallback
	var terrain_feature: GameEnums.TerrainFeature = sample.get("terrain_feature", GameEnums.TerrainFeature.NONE)
	var biome_type: GameEnums.BiomeType = sample.get("biome_type", GameEnums.BiomeType.MOORLAND)
	return terrain_feature != GameEnums.TerrainFeature.MARSH and terrain_feature != GameEnums.TerrainFeature.PEAT_BOG and biome_type != GameEnums.BiomeType.OCEAN

## Sub-cell biome at `world_pos` resolved against `hex_coord`, or `fallback`
## outside the baked corridor. Public for BuildingManager.get_placement_error()
## (Phase 3b) — a building's `allowed_biomes` restriction reads the real
## terrain under its exact footprint instead of the macro hex's single
## majority-voted biome_type.
static func biome_at(hex_coord: Vector2i, world_pos: Vector2, fallback: GameEnums.BiomeType) -> GameEnums.BiomeType:
	var sample := sample_at_world_within(hex_coord, world_pos)
	if sample.is_empty():
		return fallback
	return sample.get("biome_type", fallback)
