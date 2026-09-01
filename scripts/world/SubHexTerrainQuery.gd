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
## sample, never in place — the cache holds raw baked-raster data only, so a
## disc that later grows or is cleared can't leave a stale paved sub-cell
## behind.
##
## ## What this cache costs, and what bounds it
##
## scripts/test/bench_subhex_cache.gd prints the current state of every number
## below, and is where a change to any of this gets re-measured. The
## before-figures are the same measurements run against the pre-change class.
##
## The cache was unbounded, static, and keyed by a per-call
## "<hex.x>_<hex.y>_<sub.x>_<sub.y>" String. Filling it with 400,000 distinct
## sub-cells — under four hexes' worth, and one fully-walked hex edge strands
## ~178 of them (SubHexPortalGraph's own measurement: 334 lookups over ~167
## positions, against two hexes each) — cost 324.7 MB resident at 851 bytes
## per entry, and none of it ever came back. Same fill now: 11.0 MB at 84
## bytes per live entry, 137,858 addresses held out of 400,000 touched. A warm
## lookup went 2.06 us -> 0.91 us on identical benchmark code.
##
## Three changes, one per cost:
##
## - **The address is a packed 60-bit integer** (_address_key()), so a warm
##   lookup shifts and hashes an int instead of allocating a String.
## - **The sample is interned.** The baked rasters have a small palette:
##   2,661,336 sub-cells — every single one across 24 real corridor hexes —
##   hold 985 distinct terrain values between them. One shared Dictionary per
##   distinct VALUE replaces one per ADDRESS. Safe for exactly the reason
##   sample() could already hand `base` straight back by reference: nothing
##   downstream mutates a returned sample, and the urban override has always
##   duplicated first. verify_subhex_cache.gd holds that second claim down,
##   since interning is what makes an in-place override cross hex boundaries.
## - **The address map is bounded** by a two-generation rollover
##   (_remember()): at MAX_ADDRESSES_PER_GENERATION the hot map becomes the
##   cold one, a fresh hot map starts, and the previous cold map is dropped
##   whole. A hit in cold moves back into hot and is erased from cold, so the
##   two maps stay disjoint and a working set smaller than one generation
##   survives a rollover it straddles. Chosen over HordeFlowField's FIFO-array
##   cap because at this cardinality the order list would itself be a
##   six-figure Array of keys; a rollover is O(1) with no per-entry
##   bookkeeping and keeps between 1x and 2x a generation of a spatially-local
##   working set.
##
## Evicting can never be wrong here, which is why none of the above has to be
## precise: every entry memoises static baked data, so anything dropped
## re-derives to the identical value at the cost of one raster read.
##
## It is not free, though, and one planned change is costed against the
## opposite assumption. backlog.md's vector-terrain phase 2 swaps the
## cache-miss body below for a point-in-polygon test against the vector set,
## and argues its cost away with "point-in-polygon runs once per cell ever
## touched." With a rollover that holds only while the working set fits in a
## generation; past that, a cycling working set re-runs the test each time it
## comes round. That item's own mitigation — a per-hex polygon bucket index —
## is what makes the recurring cost affordable, so it stops being optional.

## Sub indices run 0..SUB_HEX_GRID_N-1 (0..332), so 9 bits each; each axial
## coordinate gets a biased 21-bit field, covering +/-1,048,576 hexes against
## a 154x179 map (BritishGeographyData's MAP_BOUNDS). 60 bits total, inside
## GDScript's signed 64-bit int with room to spare.
const _KEY_SUB_BITS: int = 9
const _KEY_HEX_BITS: int = 21
const _KEY_HEX_BIAS: int = 1 << (_KEY_HEX_BITS - 1)

## Live addresses per generation; the cache holds between this and twice it.
## Sized against the two numbers that decide it rather than a round figure.
##
## An interned entry measures 84 bytes, so the hard ceiling here is
## 2 x 131,072 x 84 B = 21.0 MB, against the 324.7 MB the same fill cost
## unbounded — both figures in the MB the bench prints, which is 1024-based.
##
## And one hex's whole address space is SUB_HEX_GRID_N^2 = 110,889 sub-cells,
## so a single generation holds every sub-cell of a hex a mechanic is working
## inside with room over. That is the floor this must not be trimmed below:
## under 110,889 a full-hex sweep would roll the generation over on itself and
## re-sample ground it had already read.
const MAX_ADDRESSES_PER_GENERATION: int = 131072

## Hard cap on distinct interned samples, so a future finer bake cannot quietly
## turn the intern table into the unbounded static Dictionary this change
## removed. Past it samples are simply not shared — slower and heavier, never
## wrong.
##
## Headroom, measured rather than assumed: sampling the whole 3,876-hex
## corridor at every 15th sub-cell found 4,190 distinct values (785 distinct
## elevations), and sampling 24 hexes at every sub-cell rather than every 15th
## found 1.47x what the same 24 hexes gave at stride 15 — so the corridor's
## full-density palette is order 6,000, about a tenth of this.
const MAX_INTERNED_SAMPLES: int = 65536

static var _cache: Dictionary = {}    # int address key -> the interned Dictionary for that sub-cell (RealTerrainSampler.sample_at()'s own shape; {} is interned too, so an off-corridor miss isn't re-queried every call)
static var _cold: Dictionary = {}     # The previous generation of the same map: read through on a miss in _cache, MOVED back into it on a hit, and dropped whole on the next rollover.
static var _interned: Dictionary = {} # [biome_type, terrain_feature, elevation_m, elevation] -> the one shared Dictionary carrying those values.

## Terrain at sub-cell `sub_index` within macro-hex `hex_coord`.
static func sample(hex_coord: Vector2i, sub_index: Vector2i) -> Dictionary:
	var key := _address_key(hex_coord, sub_index)
	var base: Dictionary
	if _cache.has(key):
		base = _cache[key]
	elif _cold.has(key):
		base = _cold[key]
		_cold.erase(key)  # Moved, not copied — the two generations stay disjoint, so cache_size() counts addresses rather than map slots.
		_remember(key, base)
	else:
		var sampled_pos := HexCoord.sub_hex_to_world(hex_coord, sub_index)
		base = _intern(RealTerrainSampler.sample_at_hex(hex_coord, sampled_pos))  # Prefers the fine per-hex tile when one's baked, same as sample_grid() already does — a plain sample_at() would silently lose that fidelity near the starting settlement.
		_remember(key, base)
	if not SubHexTerrainOverride.has_urban_disc(hex_coord):
		return base  # Overwhelmingly the common case — one dictionary lookup, and the cached result is returned by reference exactly as before overrides existed.
	return _with_urban_override(hex_coord, HexCoord.sub_hex_to_world(hex_coord, sub_index), base)

## One sub-cell address as a single int — see the constants above for the
## layout. Runs on every lookup, hit or miss, and allocates nothing.
static func _address_key(hex_coord: Vector2i, sub_index: Vector2i) -> int:
	var hex_field := ((hex_coord.x + _KEY_HEX_BIAS) << _KEY_HEX_BITS) | (hex_coord.y + _KEY_HEX_BIAS)
	return (hex_field << (_KEY_SUB_BITS * 2)) | (sub_index.x << _KEY_SUB_BITS) | sub_index.y

## Records one address in the hot generation, rolling over first if it is
## full. The map dropped is the OLDER of the two, so anything touched since
## the last rollover survives this one.
static func _remember(key: int, interned_sample: Dictionary) -> void:
	if _cache.size() >= MAX_ADDRESSES_PER_GENERATION:
		_cold = _cache
		_cache = {}
	_cache[key] = interned_sample

## The one shared Dictionary carrying `sampled`'s values, so N sub-cells over
## the same terrain cost one sample between them rather than N. Keyed on an
## Array of the four fields rather than a formatted String: Variant hashing
## compares the floats exactly, so there is no precision question about
## elevation_m, whose raster steps are 1/256 m.
static func _intern(sampled: Dictionary) -> Dictionary:
	var content: Array = [
		sampled.get("biome_type"),
		sampled.get("terrain_feature"),
		sampled.get("elevation_m"),
		sampled.get("elevation"),
	]
	if _interned.has(content):
		return _interned[content]
	if _interned.size() >= MAX_INTERNED_SAMPLES:
		return sampled
	_interned[content] = sampled
	return sampled

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

## Clears both generations and the intern table — only meaningful for
## tests/tooling; the underlying bake data is static for the lifetime of a
## running game, so production code never needs this. Mirrors no existing
## precedent 1:1, but avoids the cache silently becoming impossible to reset
## if a future phase (or a test) ever needs a clean slate.
static func clear_cache() -> void:
	_cache.clear()
	_cold.clear()
	_interned.clear()

## Live address count across both generations, which hold disjoint key sets
## (sample() erases a promoted key from cold) — a caller that fans out over
## many sub-cells (SubHexPortalGraph walking whole hex edges) needs a way to
## measure what it strands here. Bounded by 2 x MAX_ADDRESSES_PER_GENERATION.
## Tests/tooling only.
static func cache_size() -> int:
	return _cache.size() + _cold.size()

## Distinct terrain values currently shared across those addresses — the
## other half of what the cache holds, and the number MAX_INTERNED_SAMPLES is
## sized against. Tests/tooling only.
static func interned_sample_count() -> int:
	return _interned.size()

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
