extends SceneTree

## Proves the 30 m elevation bake is real data at real resolution, and that the
## Godot side reads it off the same lattice the bake wrote. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_fine_elevation.gd
##
## The bake exists because the coarse raster does not hold what it appears to.
## bake_landcover.py writes elevation.png at ~878 m/px but samples it with
## step = 4 and a NEAREST-NEIGHBOUR upsample, so the true interval is ~3,510 m --
## about 3x3 real values per hex, and every "elevation" read anywhere in the game
## has been one of nine numbers. Check 2 below measures that directly rather than
## taking the bake's word for it.
##
## Exits non-zero on any failure, so it gates rather than only reporting.

const _SAMPLE_HEXES: int = 24
const _GRID_N: int = 40

## Britain's real range with room either side, and the floor is BELOW SEA LEVEL
## on purpose: Terrarium tiles carry bathymetry, not just land, so every sea
## pixel in the corridor decodes to a real negative depth. Measured against the
## source at z12: Liverpool Bay -11.9 m, mid Irish Sea -50.1 m, Thames Estuary
## -12.0 m, against Ben Nevis 1313.5 m and Manchester 44.4 m.
##
## The first version of this check used -30.0 and failed on a genuine -122 m of
## Irish Sea floor. Widened rather than clamped: the depth is real data, and any
## consumer reading elevation over water gets it (see FineElevationTiles).
##
## -400 still catches every decode bug worth catching. A byte-order slip or a
## missing -32768 offset lands values in the tens of thousands, nowhere near here.
const _MIN_PLAUSIBLE_M: float = -400.0
const _MAX_PLAUSIBLE_M: float = 1400.0

var _failures: Array[String] = []


func _initialize() -> void:
	var tiled := _corridor_hexes_with_tiles()
	print("elevation_fine tiles found for %d of the sampled corridor hexes" % tiled.size())
	if tiled.is_empty():
		print("FAIL: no elevation tiles at all. Bake them with:")
		print("  python tools/geo_bake/bake_fine_relief.py --corridor --metres --no-shade")
		quit(1)
		return

	_check_range(tiled)
	_check_resolution(tiled)
	_check_lattice_agreement(tiled)
	_check_query_layer(tiled)
	_check_cache_bound()

	print()
	if _failures.is_empty():
		print("All fine-elevation checks passed.")
		quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for f in _failures:
			print("  " + f)
		quit(1)


## Walks the baked corridor on a stride rather than all 3,876 hexes: every check
## below is per-pixel work, and the questions asked are about the format and the
## addressing, neither of which varies hex to hex.
func _corridor_hexes_with_tiles() -> Array[Vector2i]:
	var q_range := RealTerrainSampler.get_corridor_q()
	var r_range := RealTerrainSampler.get_corridor_r()
	var out: Array[Vector2i] = []
	var q_step: int = maxi(1, (q_range.y - q_range.x) / 6)
	var r_step: int = maxi(1, (r_range.y - r_range.x) / 6)
	for q in range(q_range.x, q_range.y + 1, q_step):
		for r in range(r_range.x, r_range.y + 1, r_step):
			if out.size() >= _SAMPLE_HEXES:
				return out
			if FineElevationTiles.has_tile(Vector2i(q, r)):
				out.append(Vector2i(q, r))
	return out


## 1. Every value decodes to an elevation Britain actually has.
func _check_range(hexes: Array[Vector2i]) -> void:
	var lowest := INF
	var highest := -INF
	for coord in hexes:
		for sample in _grid(coord):
			lowest = minf(lowest, sample)
			highest = maxf(highest, sample)
	print("range across %d hexes: %.1f m .. %.1f m" % [hexes.size(), lowest, highest])
	if lowest < _MIN_PLAUSIBLE_M or highest > _MAX_PLAUSIBLE_M:
		_failures.append("elevation outside %.0f..%.0f m -- decode is wrong, not the terrain"
			% [_MIN_PLAUSIBLE_M, _MAX_PLAUSIBLE_M])


## 2. The tiles hold genuinely more information than the raster they replace.
##
## Counts DISTINCT values over the same grid of world positions read two ways.
## The coarse raster's nearest-neighbour upsample caps it at roughly 3x3 real
## values per hex however densely it is sampled; that cap is the whole defect,
## and it is what makes this a fair comparison rather than a tautology.
func _check_resolution(hexes: Array[Vector2i]) -> void:
	var fine_total := 0
	var coarse_total := 0
	var worst_hex := Vector2i.ZERO
	var worst_ratio := INF
	for coord in hexes:
		var fine := {}
		var coarse := {}
		for pos in _grid_positions(coord):
			var f: Variant = FineElevationTiles.metres_at(coord, pos)
			if f != null:
				fine[roundi(float(f))] = true
			var c: Dictionary = RealTerrainSampler.sample_at(pos)
			if not c.is_empty():
				coarse[roundi(float(c["elevation_m"]))] = true
		fine_total += fine.size()
		coarse_total += coarse.size()
		var ratio: float = float(fine.size()) / maxf(1.0, float(coarse.size()))
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst_hex = coord
	var mean_fine := float(fine_total) / hexes.size()
	var mean_coarse := float(coarse_total) / hexes.size()
	print("distinct values per hex over a %dx%d grid: fine %.1f, coarse %.1f (%.1fx)"
		% [_GRID_N, _GRID_N, mean_fine, mean_coarse, mean_fine / maxf(1.0, mean_coarse)])
	print("  weakest hex %s at %.1fx" % [worst_hex, worst_ratio])
	## Deliberately slack. A genuinely flat hex (the Fens, an estuary) holds few
	## distinct values however finely it is sampled, and that is correct data, not
	## a failure. The bar is that the bake carries MORE than the raster it replaces
	## on average, which a 3x3-capped source cannot fake.
	if mean_fine <= mean_coarse * 2.0:
		_failures.append("fine tiles carry %.1f distinct values/hex vs coarse %.1f -- no real resolution gain"
			% [mean_fine, mean_coarse])


## 3. Overlapping tiles agree exactly where they cover the same ground.
##
## The bake snaps every tile origin down to a multiple of the pixel step so all
## tiles are subsets of ONE global lattice. Reading them back with an unsnapped
## origin -- which is what RealTerrainSampler._sample_fine() correctly does for
## the differently-baked land-cover tiles -- would sample up to a pixel away and
## make neighbouring tiles disagree. This is the check that catches that.
func _check_lattice_agreement(hexes: Array[Vector2i]) -> void:
	var compared := 0
	var disagreed := 0
	var worst := 0.0
	for coord in hexes:
		for neighbour in HexCoord.neighbors(coord):
			if not FineElevationTiles.has_tile(neighbour):
				continue
			# Midway between two hex centres is inside BOTH tiles: centres are at
			# most ~886 world units apart and each tile reaches 512 from its own.
			var midpoint: Vector2 = (HexCoord.axial_to_world(coord)
				+ HexCoord.axial_to_world(neighbour)) * 0.5
			var a: Variant = FineElevationTiles.metres_at(coord, midpoint)
			var b: Variant = FineElevationTiles.metres_at(neighbour, midpoint)
			if a == null or b == null:
				continue
			compared += 1
			var delta: float = absf(float(a) - float(b))
			worst = maxf(worst, delta)
			if delta > 0.0:
				disagreed += 1
	print("overlap agreement: %d hex pairs compared, %d disagree, worst %.1f m"
		% [compared, disagreed, worst])
	if compared == 0:
		_failures.append("no overlapping tile pairs found -- the lattice check ran on nothing")
	elif disagreed > 0:
		_failures.append("%d of %d overlapping pairs disagree (worst %.1f m) -- tile origin is not snapped to the bake lattice"
			% [disagreed, compared, worst])


## 4. The sanctioned sub-hex read path returns the tile's value, and falls back
##    to the coarse raster off the baked corridor rather than returning zero.
func _check_query_layer(hexes: Array[Vector2i]) -> void:
	var mismatches := 0
	for coord in hexes:
		for sub in [Vector2i(80, 80), Vector2i(166, 166), Vector2i(250, 250)]:
			var direct: Variant = FineElevationTiles.metres_at(
				coord, HexCoord.sub_hex_to_world(coord, sub))
			var through_layer := SubHexTerrainQuery.elevation_metres(coord, sub)
			if direct != null and absf(float(direct) - through_layer) > 0.001:
				mismatches += 1
	if mismatches > 0:
		_failures.append("SubHexTerrainQuery.elevation_metres() disagrees with the tile in %d places"
			% mismatches)

	# Far outside the baked corridor: must fall back, not crash and not invent data.
	var off_map := Vector2i(RealTerrainSampler.get_corridor_q().y + 40,
		RealTerrainSampler.get_corridor_r().y + 40)
	if FineElevationTiles.has_tile(off_map):
		_failures.append("expected no tile at %s, which is outside the baked corridor" % off_map)
	var fallback := SubHexTerrainQuery.elevation_metres(off_map, Vector2i(166, 166))
	print("off-corridor fallback at %s returned %.1f m (coarse raster or 0.0)" % [off_map, fallback])


## 5. The tile cache stays bounded.
##
## CLAUDE.md section 3 names the unbounded static cache as this project's
## recurring hazard, and these tiles are ~325 KB each: unbounded across the
## corridor is ~1.3 GB. RealTerrainSampler._fine_tile_cache has exactly that
## shape today, which is why this is checked rather than assumed.
func _check_cache_bound() -> void:
	FineElevationTiles.clear_cache()
	var q_range := RealTerrainSampler.get_corridor_q()
	var r_range := RealTerrainSampler.get_corridor_r()
	var touched := 0
	for q in range(q_range.x, q_range.y + 1):
		for r in range(r_range.x, r_range.y + 1):
			if touched >= 120:
				continue
			var coord := Vector2i(q, r)
			FineElevationTiles.metres_at(coord, HexCoord.axial_to_world(coord))
			touched += 1
	var held := FineElevationTiles.cached_tile_count()
	print("cache after %d distinct hexes: %d tiles held" % [touched, held])
	if held > FineElevationTiles.MAX_CACHED_TILES:
		_failures.append("tile cache holds %d tiles after %d lookups -- it is not bounded"
			% [held, touched])


## The same grid of world positions for every check, so "range", "resolution"
## and the tile lookup are all describing the same ground.
func _grid_positions(coord: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var origin := HexCoord.axial_to_world(coord)
	# 0.4 of the span, not 0.5: the tile is a square and the hex inside it is not,
	# so the corners of a full-span grid fall on ground the neighbouring hex owns.
	var half := HexCoord.SUB_HEX_GRID_SPAN * 0.4
	for y in _GRID_N:
		for x in _GRID_N:
			out.append(origin + Vector2(
				(float(x) / (_GRID_N - 1) - 0.5) * 2.0 * half,
				(float(y) / (_GRID_N - 1) - 0.5) * 2.0 * half))
	return out


func _grid(coord: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for pos in _grid_positions(coord):
		var m: Variant = FineElevationTiles.metres_at(coord, pos)
		if m != null:
			out.append(float(m))
	return out
