extends Node

## Diagnostic for the user's "I've never seen a zombie while playtesting"
## report (2026-08-26), run against their REAL "Manchester Campaign" save
## rather than a fresh generation (which per verify_gates.gd's own comment
## takes several minutes for the full UK+Ireland corridor).
##
## Measures the real distance from the settlement to every currently-live
## Horde, and separately re-derives HordeManager._spawnable_coords()'s own
## candidate set to show what its lack of an upper distance bound actually
## produces at real map scale.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_horde_spawn_distance.tscn

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
	var horde_manager: HordeManager = _main.get_node("HordeManager")

	var settlement_coords: Array[Vector2i] = []
	var all_cells := hex_grid_map.get_all_cells()
	for cell in all_cells:
		if cell.is_settlement:
			settlement_coords.append(cell.coord)
	print("total loaded cells: %d, settlement hexes: %s" % [all_cells.size(), settlement_coords])

	var hordes := horde_manager.get_all_hordes()
	print("\n=== live hordes: %d ===" % [hordes.size()])
	var distances: Array[int] = []
	for horde in hordes:
		var nearest := 999999
		for s in settlement_coords:
			nearest = mini(nearest, HexCoord.distance(horde.hex_coord, s))
		distances.append(nearest)
		print("horde id=%d size=%d coord=%s nearest_settlement_dist=%d" % [horde.id, horde.size, horde.hex_coord, nearest])

	if not distances.is_empty():
		distances.sort()
		var total := 0
		for d in distances:
			total += d
		print("\nmin=%d  median=%d  max=%d  mean=%.1f" % [distances[0], distances[distances.size() / 2], distances[-1], float(total) / distances.size()])

	# Re-derive _spawnable_coords()'s own candidate set (post-fix: MIN..MAX
	# bound, not just a lower bound) to show what a fresh horde (starting
	# seed or ambient) is actually drawn from now.
	var candidates := 0
	var candidate_dist_total := 0
	var candidate_dist_max := 0
	var within_10 := 0
	for cell in all_cells:
		if not cell.is_passable() or not cell.is_frontier():
			continue
		var nearest := 999999
		for s in settlement_coords:
			nearest = mini(nearest, HexCoord.distance(cell.coord, s))
		if nearest < HordeManager.MIN_SPAWN_DISTANCE_FROM_SETTLEMENT or nearest > HordeManager.MAX_SPAWN_DISTANCE_FROM_SETTLEMENT:
			continue
		candidates += 1
		candidate_dist_total += nearest
		candidate_dist_max = maxi(candidate_dist_max, nearest)
		if nearest <= 10:
			within_10 += 1

	print("\n=== _spawnable_coords() candidate pool post-fix (MIN=%d, MAX=%d) ===" % [HordeManager.MIN_SPAWN_DISTANCE_FROM_SETTLEMENT, HordeManager.MAX_SPAWN_DISTANCE_FROM_SETTLEMENT])
	print("total candidates: %d" % [candidates])
	if candidates > 0:
		print("mean distance from nearest settlement: %.1f, max: %d" % [float(candidate_dist_total) / candidates, candidate_dist_max])
		print("candidates within 10 hexes: %d (%.2f%%)" % [within_10, 100.0 * within_10 / candidates])

	get_tree().quit(0)
