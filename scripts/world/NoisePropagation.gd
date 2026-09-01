class_name NoisePropagation
extends RefCounted

## design_doc.md §6's "Sound & Acoustic Propagation System" as a model, not a
## lookup table: a source level in dB at a reference distance, geometric
## spreading, air absorption, and §6's terrain rules. Static and stateless
## apart from one path cache, same shape as HexCoord/HexPathfinder/
## SubHexPortalGraph — a rule about a value, not an owner of one, and its
## HexGridMap arrives as a parameter rather than a NodePath for the same
## reason SubHexPortalGraph's does.
##
## `NoiseManager` owns the per-hex attraction field and the signal wiring;
## this owns the physics. Two responsibilities, two classes (`CLAUDE.md` §1).
##
## ## Why §6's own table is NOT what a building emits
##
## §6 rates its loudest listed sound, artillery, at "40+ tiles". A tactical
## tile is 10 m (§7), so that is 400 m. A macro hex is 8,647 m centre to
## centre. **Every entry in §6's table fits inside a twentieth of one hex** —
## melee 20 m, rifle 150 m, Maxim 250 m, steam engine 120 m, construction
## 80 m. That table is written for the tactical layer, where the listener is
## an individual zombie standing on the same ground as the shot.
##
## `HordeManager`'s ATTRACTED state is strategic: it scans hexes within
## ATTRACTION_AWARENESS_RADIUS and paths toward the loudest. Implementing §6's
## radii literally would mean noise never crosses a hex boundary and no horde
## is ever drawn to anything, which deletes the counterplay `vision.md` P2
## calls the core tension engine of the game.
##
## §6 has no strategic entry at all — its only building row is "Building
## Construction, 8 tiles". So what is reproduced here is §6's *model*, applied
## to the sources that exist and have a consumer, with the loudest building
## calibrated to land where the flat aura it replaces already was. What is NOT
## reproduced is its radius table, which belongs to a tactical consumer that
## does not exist yet.

## One tactical tile (design_doc.md §7). Industrial noise is conventionally
## quoted at a stated distance, and a tile is the smallest distance this game
## has a name for.
const REFERENCE_DISTANCE_METRES: float = 10.0

## Point source in free field: -6 dB per doubling of distance, which is
## -20 dB per decade.
const SPREADING_DB_PER_DECADE: float = 20.0

## Air absorption. 2 dB/km is mid-frequency at ordinary British temperature
## and humidity — a real figure, and the term that stops the inverse-square
## law alone carrying a foundry across the county.
const AIR_ABSORPTION_DB_PER_KM: float = 2.0

## The level a zombie reacts to at all. **This is the balance knob**, and it
## is what makes strategic reach work: a real hearing threshold sits at 0 dB
## against a real ambient floor of 25-30 dBA, and this world has no competing
## sound in it — no traffic, no aircraft, and a countryside the plague
## emptied. Chosen so the catalogue's loudest building pulls a horde from
## 2.03 hexes, which is exactly where NoiseManager's flat 2-hex aura already
## reached: this lands as a change of SHAPE, not of balance.
## `scripts/test/verify_noise_emission.gd` holds that calibration down.
const HEARING_THRESHOLD_DB: float = 5.0

## Night. Added to the source rather than multiplying the field, because
## multiplying a decibel is meaningless: +6 dB is one doubling of audible
## distance under spreading, which is what "night carries further" should
## mean. Sound genuinely does propagate further after dark — a nocturnal
## temperature inversion refracts it back down instead of up.
const NIGHT_PROPAGATION_BONUS_DB: float = 6.0

## §6: "Woodland / Structures / Walls: Dampens sound propagation by -2 tiles
## per obstacle tile traversed." That rule is written per 10 m tile and a hex
## is 865 tiles across, so it is restated per kilometre of woodland the path
## actually crosses. 6 dB is one halving of audible distance per kilometre,
## which lands near §6's own severity (it takes 3 m of range off every metre
## of obstacle) without pretending to tile granularity this layer does not
## have.
const WOODLAND_ATTENUATION_DB_PER_KM: float = 6.0

## §6: "Level 2/3 Highlands reduce sound propagation radius by 50%." A 50%
## radius reduction IS 6 dB under spreading (20*log10(2) = 6.02), so this is
## §6's own number translated rather than a new one.
##
## Scaled by the SHARE of the path that is actually high ground, not applied
## whole the moment a path touches any. That is not a softening — it is what
## the first version got wrong, and the measurement caught it: HILL starts at
## 100 m (`ElevationLevels`) and most of northern England clears that, so an
## any-sample-counts rule fired on essentially every path around the starting
## corridor and became a global -6 dB rather than a property of a barrier.
## Measured before the fix: an Iron Foundry put 18.0 attraction on its
## neighbouring hex where a clear path gives 24.0, on every neighbour, in
## every direction.
const HIGH_GROUND_ATTENUATION_DB: float = 6.0

## §6: "Level 4 Mountains block sound completely."
const BLOCKED: float = INF

## Sub-cells sampled per axis when measuring one hex's woodland and
## high-ground share — 9x9 = 81 samples across a hex's 333x333 grid, which is
## a fraction estimate with roughly 5 percentage points of standard error and
## costs one 30 m terrain read each. What is being estimated is a share of a
## kilometres-long path, so that error is far below the 6 dB the share is
## multiplied into.
const HEX_OPACITY_SAMPLES_PER_AXIS: int = 9

## Per-hex opacity cap. The playable corridor is 3,876 hexes and the whole
## landmass 4,692, so this holds every hex the game has and the cap is a
## backstop rather than a working limit. Evicting can never be wrong: the value
## is a pure function of static baked terrain, so anything dropped re-derives
## to the identical number at the cost of one hex's sampling.
const MAX_CACHED_HEX_OPACITY: int = 8192

static var _opacity_cache: Dictionary = {}      # Vector2i -> [woodland_fraction, high_ground_fraction]
static var _opacity_order: Array[Vector2i] = []  # FIFO eviction order, parallel to the keys above


## Sound level in dB at `distance_metres` from a source emitting
## `source_db` at REFERENCE_DISTANCE_METRES, less `extra_attenuation_db` of
## terrain. Distance is floored at the reference distance so a listener
## standing on the source does not divide by zero or read an infinite level.
static func level_at(source_db: float, distance_metres: float, extra_attenuation_db: float = 0.0) -> float:
	if extra_attenuation_db == BLOCKED:
		return -BLOCKED
	var distance := maxf(distance_metres, REFERENCE_DISTANCE_METRES)
	var spreading := SPREADING_DB_PER_DECADE * log(distance / REFERENCE_DISTANCE_METRES) / log(10.0)
	return source_db - spreading - AIR_ABSORPTION_DB_PER_KM * distance / 1000.0 - extra_attenuation_db


## The distance at which `source_db` falls to `target_db`, or 0.0 if it never
## reaches it. Bisected rather than solved: the air-absorption term is linear
## in distance and the spreading term is logarithmic, so there is no closed
## form, and dropping the linear term to get one would overstate the radius by
## two orders of magnitude (a 108 dB source spreads to threshold at 1,400 km
## with no absorption and 18.8 km with it).
static func distance_to_level(source_db: float, target_db: float, extra_attenuation_db: float = 0.0) -> float:
	if level_at(source_db, REFERENCE_DISTANCE_METRES, extra_attenuation_db) < target_db:
		return 0.0
	var near := REFERENCE_DISTANCE_METRES
	var far := 1000000.0
	for _i in 60:
		var mid := (near + far) * 0.5
		if level_at(source_db, mid, extra_attenuation_db) >= target_db:
			near = mid
		else:
			far = mid
	return near


## Sound levels do not add: intensities do. Two equal sources on one hex are
## +3 dB, not twice as loud, so a caller accumulating several sources sums
## these and converts back with level_from_intensity(). This is the one place
## the old flat model was wrong about physics rather than about scale — its
## own comment claimed summing was "closer to how real industrial noise
## stacks", and a dense industrial district was therefore N times as
## attractive as one building instead of 10*log10(N) dB louder.
static func intensity_of(level_db: float) -> float:
	return pow(10.0, level_db / 10.0)


static func level_from_intensity(intensity: float) -> float:
	if intensity <= 0.0:
		return -BLOCKED
	return 10.0 * log(intensity) / log(10.0)


## Extra dB of terrain attenuation along the path between two hexes, or
## BLOCKED if a Level 4 mountain stands on it.
##
## Walks the hex line between the two and reads a cached per-hex opacity for
## each, rather than ray-marching the terrain per source/listener pair. **The
## first version did ray-march, and the measurement is why it does not any
## more:** at 200 buildings a recompute took 55 s and never got faster,
## because 7,400 source/listener pairs at ~70 terrain samples each both
## overran the path cache and thrashed it. Per hex instead of per pair, the
## expensive half is paid once per hex ever — bounded by the map — and a path
## costs one dictionary lookup per hex it crosses. Same measurement after:
## 200 buildings, 0.23 s cold and 41 ms warm.
##
## `CLAUDE.md` §3, stated rather than assumed: the per-hex number this caches
## is a FRACTION integrated from real 30 m sub-cell reads, not a hex-level
## classification. §3 exists to catch majority votes and "does any part of
## this hex" tests standing in for sub-hex data; a share of a hex's area, used
## as a share of a kilometres-long path integral, is the aggregate that
## quantity is actually made of. The one thing decided per MACRO hex is the
## MOUNTAIN clause, which is §3's own named exception: `MountainPassCarver`
## opens passes by lowering `HexCell.elevation` at generation and that carve
## exists nowhere in the baked raster, so a per-sub-cell test would re-seal
## every carved pass — and a carved pass is exactly where sound should get
## through.
##
## The source's own hex is excluded from the walk: a foundry is not muffled by
## the wood it cleared to build in.
static func attenuation_db(from_hex: Vector2i, to_hex: Vector2i, hex_grid_map: HexGridMap) -> float:
	if from_hex == to_hex:
		return 0.0
	var line := HexCoord.hex_line(from_hex, to_hex)
	var step_metres := HexCoord.axial_to_world(Vector2i(1, 0)).length() / HexCoord.WORLD_UNITS_PER_REAL_METER
	var woodland_metres := 0.0
	var high_ground_share := 0.0
	var counted := 0
	for i in range(1, line.size()):
		var hex: Vector2i = line[i]
		if hex_grid_map and ElevationLevels.is_impassable(_height_level_of(hex_grid_map, hex)):
			return BLOCKED
		var opacity := _opacity_of(hex)
		woodland_metres += opacity[0] * step_metres
		high_ground_share += opacity[1]
		counted += 1
	if counted == 0:
		return 0.0
	return WOODLAND_ATTENUATION_DB_PER_KM * woodland_metres / 1000.0 \
			+ HIGH_GROUND_ATTENUATION_DB * high_ground_share / float(counted)


## [woodland_fraction, high_ground_fraction] for one hex, sampled across its
## own sub-cell grid. Cached — this is the expensive call, and terrain is
## static.
##
## ## The elevation read is the COARSE one, and `CLAUDE.md` §3 asks that to be
## ## said out loud rather than built on quietly
##
## Biome comes through `SubHexTerrainQuery` at genuine 30 m fidelity (the fine
## per-hex tile, where one is baked). Elevation comes from the same class's
## `sample()["elevation"]`, which is the ~3.5 km coarse raster — NOT
## `elevation_metres()`, which §3 names as the sanctioned fine read.
##
## Measured both ways rather than argued:
##
## - **Cost.** `elevation_metres()` goes to `FineElevationTiles`, one ~27 KB
##   PNG per hex. A 200-building colony needs opacity for 360 hexes, and
##   loading a tile for each took a cold recompute from **0.23 s to 11.5 s**
##   (`scripts/test/diagnose_noise_emission.gd`, same fixture, only this line
##   changed). recompute() runs on every building placed, so that is a hitch
##   the player would feel.
## - **Error.** Over 140 real corridor hexes the coarse raster's high-ground
##   FRACTION differs from the fine one by 0.057 on average and 0.33 at worst
##   — **0.34 dB mean and 2.0 dB worst-case** once multiplied into
##   HIGH_GROUND_ATTENUATION_DB, against sources spanning 80 to 108 dB.
##
## What makes that trade defensible rather than merely cheap is what is being
## estimated: a SHARE of a 65 km2 hex, used as a share of a kilometres-long
## path. `RealTerrainSampler`'s own doc comment makes the same call for the
## same reason — the fine bake deliberately covers biome and terrain_feature
## and not elevation, "elevation varies smoothly enough at this scale that the
## coarse elevation.png is unaffected".
##
## What would change this: a consumer that needs to know WHERE in a hex the
## high ground is rather than how much of it there is. §6's line-of-sight and
## light propagation is that consumer, and it is deferred.
static func _opacity_of(hex: Vector2i) -> Array:
	if _opacity_cache.has(hex):
		return _opacity_cache[hex]
	var woodland := 0
	var high_ground := 0
	var samples := 0
	var stride := HexCoord.SUB_HEX_GRID_N / HEX_OPACITY_SAMPLES_PER_AXIS
	for row in HEX_OPACITY_SAMPLES_PER_AXIS:
		for col in HEX_OPACITY_SAMPLES_PER_AXIS:
			var sub := Vector2i(col * stride + stride / 2, row * stride + stride / 2)
			var world_pos := HexCoord.sub_hex_to_world(hex, sub)
			samples += 1
			if SubHexTerrainQuery.biome_at(hex, world_pos, GameEnums.BiomeType.MOORLAND) == GameEnums.BiomeType.WOODLAND:
				woodland += 1
			var level := ElevationLevels.level_for(
				float(SubHexTerrainQuery.sample(hex, sub).get("elevation", 0.0)), false)
			if level == ElevationLevels.HILL or level == ElevationLevels.HIGHLAND:
				high_ground += 1
	var opacity: Array = [float(woodland) / float(samples), float(high_ground) / float(samples)]
	if _opacity_cache.size() >= MAX_CACHED_HEX_OPACITY:
		_opacity_cache.erase(_opacity_order.pop_front())
	_opacity_cache[hex] = opacity
	_opacity_order.append(hex)
	return opacity


## An off-map hex has no elevation to judge and does not block — the same call
## `SubHexPortalGraph._is_mountain_blocked()` makes about a null cell.
static func _height_level_of(hex_grid_map: HexGridMap, hex: Vector2i) -> int:
	var cell := hex_grid_map.get_cell(hex)
	if cell == null:
		return ElevationLevels.SEA_LEVEL
	return cell.height_level()


## Clears the per-hex opacity cache — tests/tooling only, same rationale
## `SubHexPortalGraph.clear_cache()` gives: baked terrain is static for the
## lifetime of a running game, so production code never needs this.
static func clear_cache() -> void:
	_opacity_cache.clear()
	_opacity_order.clear()


## Live cached hex count. Bounded by MAX_CACHED_HEX_OPACITY. Tests/tooling
## only.
static func cache_size() -> int:
	return _opacity_cache.size()
