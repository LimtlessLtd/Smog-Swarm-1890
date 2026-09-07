extends SceneTree

## Locks down SubHexTerrainQuery's cache: that it is bounded, that evicting is
## invisible to a caller, that the packed address key does not collide, and
## that interning a sample cannot leak one hex's urban override into another
## hex's terrain. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_subhex_cache.gd
##
## The cache used to be unbounded, static and String-keyed: 400,000 distinct
## sub-cells cost 324.5 MB resident and never came back
## (scripts/test/bench_subhex_cache.gd has the before/after). The rewrite
## replaced all three properties at once, and each replacement has its own way
## of being silently wrong, which is what the four checks below are:
##
## 1. A cap that does not actually cap.
## 2. An eviction that changes an answer. It must not be able to — every entry
##    memoises static baked data — so this check is what keeps a future mutable
##    field from being cached here without noticing.
## 3. Two different sub-cells packing to the same 60-bit key, which would serve
##    one hex's terrain for another's. The bias-and-shift arithmetic is where
##    an off-by-one would live, so the fixture deliberately includes negative
##    hex coordinates and both ends of the sub-index range.
## 4. The failure interning newly makes possible: sub-cells over identical
##    terrain now share ONE Dictionary, so an urban disc written into that
##    shared instance rather than a duplicate would repaint terrain in hexes
##    nobody founded anything in.
##
## Exits non-zero on any failure, so it gates rather than only reporting.

## Enough to roll the two generations over twice, so the check is measuring a
## cache that has actually evicted rather than one that never filled.
const _FLOOD_ADDRESSES: int = SubHexTerrainQuery.MAX_ADDRESSES_PER_GENERATION * 3

## Mid-corridor (RealTerrainSampler's own corridor is q 55..105, r 85..160), so
## the fixture reads real baked raster and real fine tiles rather than the {}
## every off-corridor address returns.
const _FIXTURE_ORIGIN := Vector2i(80, 120)

## The flood walks its own hexes, disjoint from every hex _fixture_addresses()
## names. Overlapping them would leave whichever fixture addresses happen to
## land in the surviving generation resident, and the eviction check would then
## compare five of its seventy-two addresses against themselves. Still inside
## the corridor, so the flood pays real cold-miss costs.
const _FLOOD_ORIGIN := Vector2i(92, 140)

var _failures: Array[String] = []


func _initialize() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to verify.")
		quit(0)
		return

	_check_bounded()
	_check_eviction_is_transparent()
	_check_address_key_does_not_collide()
	_check_interning_survives_an_urban_disc()

	print()
	if _failures.is_empty():
		print("All sub-hex cache checks passed.")
		quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		quit(1)


## The cap holds under a flood of distinct addresses. Deliberately floods with
## addresses that are never revisited, which is the access pattern a cap has to
## survive — a working set that fits would never trigger a rollover at all.
func _check_bounded() -> void:
	SubHexTerrainQuery.clear_cache()
	for i in _FLOOD_ADDRESSES:
		SubHexTerrainQuery.sample(_flood_hex(i), _flood_sub_index(i))
	var held := SubHexTerrainQuery.cache_size()
	var ceiling := SubHexTerrainQuery.MAX_ADDRESSES_PER_GENERATION * 2
	print("cache after %d distinct addresses: %d held (ceiling %d), %d interned samples" % [
		_FLOOD_ADDRESSES, held, ceiling, SubHexTerrainQuery.interned_sample_count()])
	if held > ceiling:
		_failures.append("the cache holds %d addresses after %d lookups -- it is not bounded"
			% [held, _FLOOD_ADDRESSES])
	if SubHexTerrainQuery.interned_sample_count() > SubHexTerrainQuery.MAX_INTERNED_SAMPLES:
		_failures.append("the intern table holds %d samples, past its own %d cap"
			% [SubHexTerrainQuery.interned_sample_count(), SubHexTerrainQuery.MAX_INTERNED_SAMPLES])


## An answer read before a flood must be identical after it. The flood walks
## _FLOOD_ORIGIN's hexes and the fixture walks _FIXTURE_ORIGIN's, so no fixture
## address can be carried by the surviving generation: 3x the per-generation cap
## of foreign addresses evicts all 72 of them, and every re-read below is a
## genuine re-derivation from the raster.
func _check_eviction_is_transparent() -> void:
	SubHexTerrainQuery.clear_cache()
	var fixture := _fixture_addresses()
	var before: Array[Dictionary] = []
	for address in fixture:
		before.append(SubHexTerrainQuery.sample(address[0], address[1]).duplicate())

	for i in _FLOOD_ADDRESSES:
		SubHexTerrainQuery.sample(_flood_hex(i), _flood_sub_index(i))

	var changed := 0
	for index in fixture.size():
		var after := SubHexTerrainQuery.sample(fixture[index][0], fixture[index][1])
		if after != before[index]:
			changed += 1
	print("re-read %d fixture addresses after eviction: %d changed (want 0)" % [fixture.size(), changed])
	if changed > 0:
		_failures.append("%d of %d addresses read differently after being evicted -- the cache is holding something that is not a pure memoisation of baked data"
			% [changed, fixture.size()])


## Every fixture address must return exactly what the underlying sampler
## returns for that same address. A key collision shows up here as one hex
## serving another hex's terrain, which no amount of re-sampling would fix.
func _check_address_key_does_not_collide() -> void:
	SubHexTerrainQuery.clear_cache()
	var mismatched := 0
	var fixture := _fixture_addresses()
	for address in fixture:
		var hex: Vector2i = address[0]
		var sub: Vector2i = address[1]
		var direct := RealTerrainSampler.sample_at_hex(hex, HexCoord.sub_hex_to_world(hex, sub))
		if SubHexTerrainQuery.sample(hex, sub) != direct:
			mismatched += 1
	print("%d fixture addresses checked against the sampler directly: %d mismatched (want 0)" % [
		fixture.size(), mismatched])
	if mismatched > 0:
		_failures.append("%d of %d addresses disagreed with RealTerrainSampler -- the packed address key is colliding"
			% [mismatched, fixture.size()])


## Two ways the same invariant can break, because interning is what makes the
## second one possible at all: the urban override must be applied to a COPY of
## the cached sample, never written into it.
##
## Part 1 is deterministic — pave a sub-cell, then clear the disc, and it has
## to read its raw baked terrain again. An override written in place would
## leave it URBAN forever.
##
## Part 2 is the cross-hex version, and it is the one interning newly exposes:
## two sub-cells over identical terrain now share ONE Dictionary instance, so
## an in-place write in a founded hex would repaint a hex nobody founded
## anything in. Reported as a fixture problem rather than a pass if no such
## pair exists in the search region.
func _check_interning_survives_an_urban_disc() -> void:
	SubHexTerrainQuery.clear_cache()
	SubHexTerrainOverride.clear_all()

	var pair := _find_shared_sample_pair()
	if pair.is_empty():
		_failures.append("could not find two sub-cells reading identical terrain -- the fixture, not the cache, needs fixing")
		return

	var paved_hex: Vector2i = pair["paved"][0]
	var paved_sub: Vector2i = pair["paved"][1]
	var other_hex: Vector2i = pair["other"][0]
	var other_sub: Vector2i = pair["other"][1]
	var paved_before: int = SubHexTerrainQuery.sample(paved_hex, paved_sub).get("biome_type", -1)
	var other_before: int = SubHexTerrainQuery.sample(other_hex, other_sub).get("biome_type", -1)

	# Centred on the sub-cell itself, radius under half a sub-cell, so exactly
	# the one cell is inside the disc and no neighbour can carry the check.
	SubHexTerrainOverride.set_urban_disc(paved_hex, HexCoord.sub_hex_to_world(paved_hex, paved_sub),
		HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS * 0.4)

	var paved_while_founded: int = SubHexTerrainQuery.sample(paved_hex, paved_sub).get("biome_type", -1)
	var other_while_founded: int = SubHexTerrainQuery.sample(other_hex, other_sub).get("biome_type", -1)
	SubHexTerrainOverride.clear_urban_disc(paved_hex)
	var paved_after_clearing: int = SubHexTerrainQuery.sample(paved_hex, paved_sub).get("biome_type", -1)

	print("paved %s%s: %d -> %d -> %d (want %d -> URBAN %d -> %d); %s%s sharing its terrain: %d -> %d (want unchanged)" % [
		paved_hex, paved_sub, paved_before, paved_while_founded, paved_after_clearing,
		paved_before, GameEnums.BiomeType.URBAN, paved_before,
		other_hex, other_sub, other_before, other_while_founded])

	if paved_while_founded != GameEnums.BiomeType.URBAN:
		_failures.append("a sub-cell inside an urban disc read %d, not URBAN -- the override is not being applied at all" % paved_while_founded)
	if paved_after_clearing != paved_before:
		_failures.append("clearing the disc left %s%s reading %d instead of its baked %d -- the override was written into the cached sample, not a duplicate"
			% [paved_hex, paved_sub, paved_after_clearing, paved_before])
	if other_while_founded != other_before:
		_failures.append("founding in %s repainted %s%s from %d to %d -- the override was written into the sample INTERNED between them"
			% [paved_hex, other_hex, other_sub, other_before, other_while_founded])

	SubHexTerrainOverride.clear_all()


## Two addresses whose raw terrain is identical, so interning has genuinely
## handed them the same Dictionary instance. Prefers a pair in two DIFFERENT
## hexes (the stronger fixture -- an in-place override there crosses a
## settlement boundary), falling back to two sub-cells of one hex, which the
## same in-place write would also corrupt. Returns {} if the search region
## holds neither.
func _find_shared_sample_pair() -> Dictionary:
	var seen: Dictionary = {}  # A stringified sample -> the first address that produced it.
	var same_hex_pair: Dictionary = {}
	for hex_offset in 8:
		var hex := Vector2i(_FIXTURE_ORIGIN.x + hex_offset, _FIXTURE_ORIGIN.y)
		for row in 20:
			for col in 20:
				var sub := Vector2i(col * 16, row * 16)
				var sample := SubHexTerrainQuery.sample(hex, sub)
				if sample.is_empty():
					continue
				var signature := str(sample)
				if not seen.has(signature):
					seen[signature] = [hex, sub]
					continue
				var first: Array = seen[signature]
				if first[0] != hex:
					return {"paved": [hex, sub], "other": first}
				if same_hex_pair.is_empty():
					same_hex_pair = {"paved": [hex, sub], "other": first}
	return same_hex_pair


## A spread of addresses that exercises the address key's arithmetic rather
## than one comfortable corner of it: negative and positive hex coordinates,
## and both ends of the 0..SUB_HEX_GRID_N-1 sub-index range.
func _fixture_addresses() -> Array[Array]:
	var last := HexCoord.SUB_HEX_GRID_N - 1
	var subs: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(last, 0), Vector2i(0, last), Vector2i(last, last),
		Vector2i(1, last), Vector2i(last, 1), Vector2i(166, 166), Vector2i(7, 301),
	]
	var hexes: Array[Vector2i] = [
		_FIXTURE_ORIGIN, _FIXTURE_ORIGIN + Vector2i(1, 0), _FIXTURE_ORIGIN + Vector2i(0, 1),
		_FIXTURE_ORIGIN + Vector2i(3, -2), Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(-17, -23), Vector2i(153, 178),
	]
	var out: Array[Array] = []
	for hex in hexes:
		for sub in subs:
			out.append([hex, sub])
	return out


## Distinct addresses that walk hexes as well as sub-cells, so the flood is not
## one hex's fine tile answering every call.
func _flood_hex(index: int) -> Vector2i:
	var per_hex := HexCoord.SUB_HEX_GRID_N * HexCoord.SUB_HEX_GRID_N
	return Vector2i(_FLOOD_ORIGIN.x + index / per_hex, _FLOOD_ORIGIN.y)


func _flood_sub_index(index: int) -> Vector2i:
	var n := HexCoord.SUB_HEX_GRID_N
	return Vector2i(index % n, (index / n) % n)
