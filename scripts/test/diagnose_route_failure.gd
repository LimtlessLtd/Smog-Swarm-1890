extends Node

## Diagnostic for the user's "Outrider cannot find a route to that location"
## report (2026-08-20), run against their REAL save rather than a fixture.
##
## Loads the real Main.tscn + SaveLoadManager, then for the unit's own hex
## dumps, per outgoing edge: the terrain verdict, whether a gate is present,
## and EXACTLY which segments intersect the centre-to-centre crossing line
## that HexPathfinder actually tests -- separating "is there a gate on this
## edge" from "does an unbreached SOLID piece still cross the tested line".
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_route_failure.tscn

const _CAMPAIGN := "Manchester Campaign"
const _SLOT := "yu5tytgt"

var _main: Node


func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_on_map_ready()
	else:
		hex_grid_map.generation_completed.connect(_on_map_ready)


func _on_map_ready() -> void:
	var save_load: SaveLoadManager = _main.get_node("SaveLoadManager")
	save_load.set_active_campaign(_CAMPAIGN)
	if not save_load.load_game(_SLOT):
		print("FAILED to load save")
		get_tree().quit(1)
		return

	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	var unit_manager: UnitManager = _main.get_node("UnitManager")
	var wall_manager: WallManager = _main.get_node("WallManager")

	var unit: UnitInstance = unit_manager.get_all_units()[0]
	var start := unit.hex_coord
	print("unit hex = %s, total wall segments in save = %d" % [start, wall_manager.get_segments().size()])

	print("\n=== each outgoing edge of %s ===" % [start])
	for neighbor in HexCoord.neighbors(start):
		var cell := hex_grid_map.get_cell(neighbor)
		var from_world := HexCoord.axial_to_world(start)
		var to_world := HexCoord.axial_to_world(neighbor)

		# Every segment registered on either hex whose own line actually
		# crosses the centre-to-centre travel line -- i.e. the exact set
		# get_blocking_segment() scans, but WITHOUT stopping at the first hit,
		# so a gate and a solid piece on the same crossing are both visible.
		var crossing_solid := 0
		var crossing_gates := 0
		var candidates := wall_manager.get_segments_at(start)
		for segment in wall_manager.get_segments_at(neighbor):
			if not candidates.has(segment):
				candidates.append(segment)
		for segment in candidates:
			if segment.is_breached():
				continue
			if Geometry2D.segment_intersects_segment(from_world, to_world, segment.point_a, segment.point_b) == null:
				continue
			if segment.is_gate:
				crossing_gates += 1
			else:
				crossing_solid += 1

		var gate_offset = wall_manager.get_gate_crossing_offset(start, neighbor)
		var blocker := wall_manager.get_blocking_segment(start, neighbor, from_world, to_world, true)
		var passable := cell != null and cell.is_passable()
		var water := HexPathfinder.is_water_crossing_blocked(hex_grid_map, null, start, neighbor)
		var biome: String = GameEnums.BiomeType.keys()[cell.biome_type] if cell else "NULL"
		var feature: String = GameEnums.TerrainFeature.keys()[cell.terrain_feature] if cell else "NULL"

		print("\n-> %s  biome=%s feature=%s passable=%s water_blocked=%s" % [neighbor, biome, feature, passable, water])
		print("   segments crossing the centre-to-centre line: %d SOLID, %d gate(s)" % [crossing_solid, crossing_gates])
		print("   a gate exists somewhere on this edge (get_gate_crossing_offset): %s" % ["yes" if gate_offset != null else "no"])
		print("   get_blocking_segment(ignore_gates=true) -> %s" % [("BLOCKED by solid id=%d" % blocker.id) if blocker else "open"])
		var edge_ok := passable and not water and blocker == null
		print("   => pathfinder accepts this edge: %s" % [edge_ok])

	print("\n=== summary ===")
	var solid_only_blocks := 0
	for neighbor in HexCoord.neighbors(start):
		var cell := hex_grid_map.get_cell(neighbor)
		if cell == null or not cell.is_passable():
			continue
		if HexPathfinder.is_water_crossing_blocked(hex_grid_map, null, start, neighbor):
			continue
		var from_world := HexCoord.axial_to_world(start)
		var to_world := HexCoord.axial_to_world(neighbor)
		if wall_manager.get_blocking_segment(start, neighbor, from_world, to_world, true) != null \
				and wall_manager.get_gate_crossing_offset(start, neighbor) != null:
			solid_only_blocks += 1
	print("edges that are terrain-OK, have a gate, and are STILL wall-blocked: %d" % [solid_only_blocks])

	# End-to-end: can the unit actually route anywhere now?
	var logistics: LogisticsNetwork = _main.get_node("LogisticsNetwork")
	var visited := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var next_frontier: Array[Vector2i] = []
		for current in frontier:
			for neighbor in HexCoord.neighbors(current):
				if visited.has(neighbor):
					continue
				var cell := hex_grid_map.get_cell(neighbor)
				if not cell or not cell.is_passable():
					continue
				if HexPathfinder.is_water_crossing_blocked(hex_grid_map, logistics, current, neighbor):
					continue
				if wall_manager.get_blocking_segment(current, neighbor, HexCoord.axial_to_world(current), HexCoord.axial_to_world(neighbor), true):
					continue
				if HexPathfinder.is_boundary_impassable(hex_grid_map, current, neighbor):
					continue
				visited[neighbor] = true
				next_frontier.append(neighbor)
		frontier = next_frontier
	print("hexes reachable from %s: %d" % [start, visited.size()])

	# Route to a genuinely distant reachable hex, the real in-game call.
	var far := start
	for coord in visited:
		if HexCoord.distance(start, coord) > HexCoord.distance(start, far):
			far = coord
	var path := HexPathfinder.find_path(hex_grid_map, start, far, logistics, wall_manager, true)
	print("find_path(%s -> %s, distance %d) = %d hexes" % [start, far, HexCoord.distance(start, far), path.size()])
	print("RESULT: %s" % ["PASS -- the unit can leave its hex and route across the map" if path.size() > 1 else "FAIL -- still sealed in"])

	get_tree().quit(0 if path.size() > 1 else 1)
