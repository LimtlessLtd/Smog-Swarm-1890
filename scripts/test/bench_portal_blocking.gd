extends Node

## Measures what HexPathfinder.is_boundary_impassable() actually costs before
## it is trusted in three hot neighbor-expansion loops.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_portal_blocking.tscn
##
## The concern is specific and worth measuring rather than reasoning about:
## SubHexPortalGraph.find_portals() walks a whole shared hex edge at 30 m
## (HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS), which is ~167 positions, each
## asking SubHexTerrainQuery twice. find_portals() caches per hex PAIR, but
## SubHexTerrainQuery caches per SUB-CELL under a string key — so the question
## is not just wall-clock, it is how many cache entries a real routing session
## strands in a static Dictionary that is never evicted.
##
## Builds only the hexes it measures, from real corridor coordinates sampled
## straight out of RealTerrainSampler, rather than running HexMapGenerator over
## the whole map — full generation is minutes of work (see
## scripts/test/verify_gates.gd's own note) and none of it is what this times.
## The coordinates are inside RealTerrainSampler's baked corridor so the
## samples hit real raster data and real fine tiles, which is where the cost
## actually is; a fixture outside the corridor would return {} immediately and
## measure nothing.

const _PATCH_ORIGIN := Vector2i(80, 120)  ## Mid-corridor (RealTerrainSampler._CORRIDOR_Q/_R are 55..105 / 85..160).
const _PATCH_RADIUS: int = 6

var _map: HexGridMap


func _ready() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to measure.")
		get_tree().quit(0)
		return

	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_patch())

	get_tree().quit(_run())


## Real biome/elevation per hex, straight from the sampler — the same values
## HexMapGenerator would derive, without its geography-feature passes.
func _build_patch() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_PATCH_ORIGIN, _PATCH_RADIUS):
		var cell := HexCell.new(coord)
		var sample := RealTerrainSampler.majority_biome(coord)
		if not sample.is_empty():
			cell.biome_type = sample["biome_type"]
			cell.elevation = sample["elevation"]
		cells[coord] = cell
	return cells


func _run() -> int:
	var edges: Array[Array] = []
	for coord in HexCoord.hex_disk(_PATCH_ORIGIN, _PATCH_RADIUS - 1):
		for neighbor in HexCoord.neighbors(coord):
			if _map.has_cell(neighbor):
				edges.append([coord, neighbor])

	SubHexTerrainQuery.clear_cache()
	SubHexPortalGraph.clear_cache()

	var cold_start := Time.get_ticks_msec()
	var blocked := 0
	for edge in edges:
		if HexPathfinder.is_boundary_impassable(_map, edge[0], edge[1]):
			blocked += 1
	var cold_ms := Time.get_ticks_msec() - cold_start

	var warm_start := Time.get_ticks_msec()
	for edge in edges:
		HexPathfinder.is_boundary_impassable(_map, edge[0], edge[1])
	var warm_ms := Time.get_ticks_msec() - warm_start

	print("edges measured:            %d" % edges.size())
	print("blocked by sub-hex terrain: %d (%.1f%%)" % [blocked, 100.0 * float(blocked) / maxf(float(edges.size()), 1.0)])
	print("cold pass:                 %d ms  (%.2f ms/edge)" % [cold_ms, float(cold_ms) / maxf(float(edges.size()), 1.0)])
	print("warm pass (all cached):    %d ms" % warm_ms)

	# The number that decides whether this is safe to leave switched on: the
	# whole playable corridor is ~3,876 hexes, so extrapolating both the time
	# and the stranded sub-cell cache entries from this patch is what says
	# whether a full session pays this once or drowns in it.
	var per_edge_subcells := float(SubHexTerrainQuery.cache_size()) / maxf(float(edges.size()), 1.0)
	print("sub-cell cache entries:    %d  (%.0f per edge)" % [SubHexTerrainQuery.cache_size(), per_edge_subcells])
	print("extrapolated to ~11,600 corridor edges: %.1f s cold, %.0f cache entries" % [
		float(cold_ms) / maxf(float(edges.size()), 1.0) * 11600.0 / 1000.0,
		per_edge_subcells * 11600.0,
	])
	return 0
