extends Node

## Measures what HexPathfinder.is_boundary_impassable() does to the map before
## it is trusted: does the sub-hex boundary rule ever actually fire, and does
## it strand ground that was reachable without it?
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_boundary_connectivity.tscn
##
## Same role and same reasoning as scripts/test/verify_elevation.gd, which
## exists because the MOUNTAIN rule turned out to strand 28 walkable hexes:
## a passability rule that looks conservative can still wall off a pocket, and
## the player meets that as "my units refuse to go there" rather than as
## terrain. This rule is the same shape of risk one level down — it blocks
## EDGES rather than hexes, so it can sever two perfectly walkable hexes.
##
## Reports the DELTA against the same map without the rule, not a raw
## unreachable count: Ireland has no land bridge to Great Britain and is
## legitimately unreachable on foot either way. The question worth answering
## is whether the new rule strands ground that used to be reachable.
##
## Also reports how many edges it blocks at all. A rule that fires zero times
## across the whole corridor is untested code rather than a safe one, and that
## is worth knowing explicitly instead of reading a clean pass as proof.
##
## Exits non-zero if the rule strands previously-reachable ground, so this is
## usable as a gate rather than only as a report.

var _map: HexGridMap
var _cells: Dictionary = {}


func _ready() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to measure.")
		get_tree().quit(0)
		return
	_cells = _build_corridor()
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_cells)
	get_tree().quit(_run())


## Real biome/elevation for every hex in the baked corridor, sampled directly
## rather than through HexMapGenerator.
##
## HexMapGenerator's named-geography and district passes are skipped
## deliberately: they place a handful of hand-authored features and none of
## them feed either rule under test, while running the full generator is
## minutes of work per run. Two things it does are reproduced, because both
## decide passability and leaving either out makes the measurement a lie:
##
##   - WETLAND -> MARSH (_apply_real_terrain()'s own biome match). majority_biome()
##     returns no terrain_feature key at all, so without this every hex reads
##     walkable and the connectivity delta compares two identical maps.
##   - MountainPassCarver, the pass that decides which mountain hexes stay
##     blocking — and exactly the verdict SubHexPortalGraph consults.
func _build_corridor() -> Dictionary:
	var q_range := RealTerrainSampler.get_corridor_q()
	var r_range := RealTerrainSampler.get_corridor_r()
	var cells: Dictionary = {}
	for q in range(q_range.x, q_range.y + 1):
		for r in range(r_range.x, r_range.y + 1):
			var coord := Vector2i(q, r)
			var cell := HexCell.new(coord)
			var sample := RealTerrainSampler.majority_biome(coord)
			if sample.is_empty():
				continue  ## Outside the baked data — no real terrain to judge.
			cell.biome_type = sample["biome_type"]
			cell.elevation = sample["elevation"]
			match cell.biome_type:
				GameEnums.BiomeType.WETLAND:
					cell.terrain_feature = GameEnums.TerrainFeature.MARSH
				GameEnums.BiomeType.HIGHLAND:
					cell.terrain_feature = GameEnums.TerrainFeature.ESCARPMENT
				GameEnums.BiomeType.WATERWAY:
					cell.terrain_feature = sample.get("water_feature_type", GameEnums.TerrainFeature.RIVER)
			cells[coord] = cell
	var carved := MountainPassCarver.carve(cells)
	var impassable := 0
	for coord: Vector2i in cells:
		if not cells[coord].is_passable():
			impassable += 1
	print("corridor hexes with real data: %d (impassable: %d, mountain passes carved: %d)" % [
		cells.size(), impassable, carved])
	return cells


func _run() -> int:
	var walkable: Array[Vector2i] = []
	for coord: Vector2i in _cells:
		if _cells[coord].is_passable():
			walkable.append(coord)
	walkable.sort()
	if walkable.is_empty():
		print("FAIL: no passable hex in the corridor at all.")
		return 1

	var blocked_edges := 0
	var total_edges := 0
	for coord in walkable:
		for neighbor in HexCoord.neighbors(coord):
			if not _map.has_cell(neighbor) or not _cells[neighbor].is_passable():
				continue
			if coord < neighbor:  ## Count each undirected edge once.
				total_edges += 1
				if HexPathfinder.is_boundary_impassable(_map, coord, neighbor):
					blocked_edges += 1

	print("walkable hexes: %d, walkable-to-walkable edges: %d" % [walkable.size(), total_edges])
	print("edges blocked by sub-hex boundary terrain: %d (%.2f%%)" % [
		blocked_edges, 100.0 * float(blocked_edges) / maxf(float(total_edges), 1.0)])

	var root := walkable[0]
	var without_rule := _reachable_from(root, false)
	var with_rule := _reachable_from(root, true)
	var stranded := without_rule.size() - with_rule.size()
	print("reachable from %s without the rule: %d" % [root, without_rule.size()])
	print("reachable from %s with the rule:    %d" % [root, with_rule.size()])
	print("newly stranded by the rule: %d" % stranded)

	if blocked_edges == 0:
		print("NOTE: the rule blocked nothing across the whole corridor — it is")
		print("      correct-by-vacuity here, not proven. See the fixture case in")
		print("      scripts/test/verify_boundary_blocking.gd for its firing test.")

	if stranded > 0:
		print("FAIL: the boundary rule strands %d hexes that were reachable without it." % stranded)
		return 1
	return 0


## Flood fill over walkable hexes, optionally applying the boundary rule to
## each step. Deliberately not HexPathfinder.find_path() — reachability is one
## traversal, not one search per hex.
func _reachable_from(root: Vector2i, apply_rule: bool) -> Dictionary:
	var seen: Dictionary = {root: true}
	var frontier: Array[Vector2i] = [root]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for neighbor in HexCoord.neighbors(current):
			if seen.has(neighbor) or not _map.has_cell(neighbor):
				continue
			if not _cells[neighbor].is_passable():
				continue
			if apply_rule and HexPathfinder.is_boundary_impassable(_map, current, neighbor):
				continue
			seen[neighbor] = true
			frontier.append(neighbor)
	return seen
