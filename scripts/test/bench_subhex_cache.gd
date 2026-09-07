extends Node

## Measures what SubHexTerrainQuery's cache costs per entry and per lookup, and
## how small the baked rasters' terrain palette is. Every number quoted in
## SubHexTerrainQuery.gd's own header is printed here.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_subhex_cache.tscn
##
## Four questions, because they have four separate answers:
##
## 1. **Warm lookup cost.** Every caller that hits an already-cached sub-cell
##    pays a key construction plus a Dictionary lookup. The key was a String
##    built with "%d_%d_%d_%d" per call, so this is the number an integer key
##    is supposed to move.
## 2. **Bytes per LIVE entry.** The cap has to be chosen against a real number,
##    not a round one. Resident memory added across a large cold fill, divided
##    by the entries still held at the end — not by the entries inserted, which
##    stopped being the same number once the cache started evicting.
## 3. **Boundedness.** Fill far past the cap with distinct sub-cells and print
##    what cache_size() settles at. Unbounded, this is the fill count.
## 4. **Palette size.** Interning is only worth anything if many sub-cells share
##    a terrain value, and MAX_INTERNED_SAMPLES has to be sized against how many
##    distinct ones the bake actually holds. Measured at full density and at
##    stride 15, because the ratio between them is what says whether a sparse
##    sweep of the whole corridor undercounts.
##
## Samples inside RealTerrainSampler's baked corridor, same reason
## bench_portal_blocking.gd gives: off-corridor lookups return {} immediately
## and would measure nothing. Walks sub-cells directly rather than through a
## HexGridMap, because none of what is being timed needs cells to exist.

const _PATCH_ORIGIN := Vector2i(80, 120)  ## Mid-corridor (RealTerrainSampler's corridor is q 55..105, r 85..160).

## One hex holds SUB_HEX_GRID_N^2 = 110,889 sub-cells, so this spans ~4 hexes
## — far past any cap worth setting, which is the point: the fill has to be
## able to outrun the cache to show that the cache holds.
const _STRESS_SAMPLES: int = 400000

## Small enough to stay comfortably inside any cap, so the warm pass is
## measuring lookups and not evict-and-resample.
const _WARM_SAMPLES: int = 40000
const _WARM_REPEATS: int = 10

## The palette sweep's extent. 6x4 real corridor hexes at full density is
## 2,661,336 samples and about 30 s. Widen this to
## RealTerrainSampler.get_corridor_q()/get_corridor_r() to reproduce the
## whole-corridor figure quoted in SubHexTerrainQuery.gd (4,190 distinct values,
## 785 distinct elevations) — that is 3,876 hexes and about nine minutes,
## which is why it is not the default.
const _PALETTE_Q := Vector2i(78, 83)
const _PALETTE_R := Vector2i(119, 122)

## Full density against a sparse sweep. Stride 15 is what makes a
## corridor-wide sweep affordable at all, so the ratio between the two is what
## says by how much that sweep undercounts.
const _PALETTE_STRIDES: Array[int] = [1, 15]


func _ready() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to measure.")
		get_tree().quit(0)
		return
	get_tree().quit(_run())


## The fill runs FIRST, on a process that has allocated nothing yet. Run after
## the warm pass it reads ~11% low: clear_cache() frees 40,000 entries back to
## Godot's allocator, not to the OS, so the fill reuses blocks that
## OS.get_static_memory_usage() has already counted.
func _run() -> int:
	_measure_fill()
	_measure_warm_lookup()
	_measure_palette()
	return 0


## Cost of a cache HIT, which is what nearly every real call is: the working
## set is filled once, then re-read _WARM_REPEATS times.
func _measure_warm_lookup() -> void:
	SubHexTerrainQuery.clear_cache()
	for i in _WARM_SAMPLES:
		SubHexTerrainQuery.sample(_fill_hex(i), _fill_sub_index(i))

	var start := Time.get_ticks_usec()
	for _repeat in _WARM_REPEATS:
		for i in _WARM_SAMPLES:
			SubHexTerrainQuery.sample(_fill_hex(i), _fill_sub_index(i))
	var elapsed_us := Time.get_ticks_usec() - start

	var lookups := _WARM_SAMPLES * _WARM_REPEATS
	print("warm lookups:        %d in %.1f ms  (%.3f us/lookup)" % [
		lookups, float(elapsed_us) / 1000.0, float(elapsed_us) / float(lookups)])


## Cold fill past any plausible cap. Reports what the cache settles at (the
## boundedness question) and what each LIVE entry costs in resident memory (the
## number the cap itself is chosen against).
func _measure_fill() -> void:
	SubHexTerrainQuery.clear_cache()
	# One touch per hex the fill will cross, BEFORE the baseline reading:
	# RealTerrainSampler loads a 333x333 fine tile per hex and holds it in its
	# own cache, and ~440 KB per tile against a ~10 MB measurement is not a
	# cost this is trying to attribute to the sub-cell cache.
	for i in range(0, _STRESS_SAMPLES, HexCoord.SUB_HEX_GRID_N * HexCoord.SUB_HEX_GRID_N):
		SubHexTerrainQuery.sample(_fill_hex(i), _fill_sub_index(i))

	var memory_before := OS.get_static_memory_usage()
	var start := Time.get_ticks_usec()
	for i in _STRESS_SAMPLES:
		SubHexTerrainQuery.sample(_fill_hex(i), _fill_sub_index(i))
	var elapsed_us := Time.get_ticks_usec() - start
	var memory_added := OS.get_static_memory_usage() - memory_before
	var entries := SubHexTerrainQuery.cache_size()

	print("cold fill:           %d distinct sub-cells in %.2f s  (%.1f us/miss)" % [
		_STRESS_SAMPLES, float(elapsed_us) / 1000000.0, float(elapsed_us) / float(_STRESS_SAMPLES)])
	print("cache after fill:    %d entries (fill was %d — equal means unbounded)" % [entries, _STRESS_SAMPLES])
	print("interned samples:    %d distinct terrain values shared across them" % SubHexTerrainQuery.interned_sample_count())
	print("resident memory:     %.1f MB added  (%.0f bytes per live entry)" % [
		float(memory_added) / 1048576.0, float(memory_added) / maxf(float(entries), 1.0)])
	print("ceiling at this cost: %.1f MB  (2 x %d live entries)" % [
		float(memory_added) / maxf(float(entries), 1.0) * float(SubHexTerrainQuery.MAX_ADDRESSES_PER_GENERATION) * 2.0 / 1048576.0,
		SubHexTerrainQuery.MAX_ADDRESSES_PER_GENERATION])


## How many distinct terrain values the bake actually holds over a region, at
## each stride. Counts through RealTerrainSampler directly rather than through
## the cache, so the answer is a property of the baked data and not of whatever
## the cache happened to still be holding.
func _measure_palette() -> void:
	var hexes := (_PALETTE_Q.y - _PALETTE_Q.x + 1) * (_PALETTE_R.y - _PALETTE_R.x + 1)
	var counts: Array[int] = []
	for stride in _PALETTE_STRIDES:
		var distinct: Dictionary = {}
		var elevations: Dictionary = {}
		var sampled := 0
		for q in range(_PALETTE_Q.x, _PALETTE_Q.y + 1):
			for r in range(_PALETTE_R.x, _PALETTE_R.y + 1):
				var hex := Vector2i(q, r)
				for sy in range(0, HexCoord.SUB_HEX_GRID_N, stride):
					for sx in range(0, HexCoord.SUB_HEX_GRID_N, stride):
						var terrain := RealTerrainSampler.sample_at_hex(hex, HexCoord.sub_hex_to_world(hex, Vector2i(sx, sy)))
						sampled += 1
						if terrain.is_empty():
							continue
						distinct[[terrain["biome_type"], terrain["terrain_feature"], terrain["elevation_m"], terrain["elevation"]]] = true
						elevations[float(terrain["elevation_m"])] = true
		counts.append(distinct.size())
		print("palette stride %-2d:    %d samples over %d hexes -> %d distinct values, %d distinct elevations" % [
			stride, sampled, hexes, distinct.size(), elevations.size()])
	if counts.size() == 2 and counts[1] > 0:
		print("full density finds %.2fx what stride %d does — a sparse corridor sweep undercuts by that much" % [
			float(counts[0]) / float(counts[1]), _PALETTE_STRIDES[1]])


## A distinct address per `i`: row-major within a hex's 333x333 grid, then on to
## the next hex. Row-major on purpose — it is the cheapest traversal that visits
## every address exactly once, and the cold-miss cost it measures is therefore a
## LOWER bound (consecutive cells in a row share a coarse raster pixel where no
## fine tile is baked). What is being sized here is the cache, not the sampler.
func _fill_hex(index: int) -> Vector2i:
	var per_hex := HexCoord.SUB_HEX_GRID_N * HexCoord.SUB_HEX_GRID_N
	return Vector2i(_PATCH_ORIGIN.x + index / per_hex, _PATCH_ORIGIN.y)


func _fill_sub_index(index: int) -> Vector2i:
	var n := HexCoord.SUB_HEX_GRID_N
	return Vector2i(index % n, (index / n) % n)
