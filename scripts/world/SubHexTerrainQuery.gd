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
## Multiple adjacent 30m sub-cells alias to the same underlying ~104m-pixel
## fine-tile value (where a fine tile is baked) or ~878m-pixel coarse value
## (elsewhere) until Phase 1b rebakes at real 30m-equivalent resolution —
## expected for this phase, not a bug: this class proves the addressing/
## caching plumbing works, not real-world fidelity yet.
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
## No write/mutation path — read-only. A sparse mutation store (matching
## ReclamationManager._drained_hexes's own pattern) lands with whichever
## later phase first needs to actually change a sub-cell (Phase 3 at the
## earliest) — building it now with no consumer would be speculative.

static var _cache: Dictionary = {}  # "<hex.x>_<hex.y>_<sub.x>_<sub.y>" -> Dictionary (RealTerrainSampler.sample_at()'s own shape, {} cached too so a miss isn't re-queried every call)

## Terrain at sub-cell `sub_index` within macro-hex `hex_coord`.
static func sample(hex_coord: Vector2i, sub_index: Vector2i) -> Dictionary:
	var key := "%d_%d_%d_%d" % [hex_coord.x, hex_coord.y, sub_index.x, sub_index.y]
	if _cache.has(key):
		return _cache[key]
	var world_pos := HexCoord.sub_hex_to_world(hex_coord, sub_index)
	var result := RealTerrainSampler.sample_at_hex(hex_coord, world_pos)  # Prefers the fine per-hex tile when one's baked, same as sample_grid() already does — a plain sample_at() would silently lose that fidelity near the starting settlement.
	_cache[key] = result
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
## (SubHexGroundView's render grid) where a position near the grid's own
## edge/corner may geometrically overhang into a neighboring hex
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
