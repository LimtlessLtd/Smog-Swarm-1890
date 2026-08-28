extends Node

## What design_doc.md §2.1's model actually does on the REAL map, rather than on
## verify_infestation.gd's flat 10,000-capacity fixture. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_infestation_pressure.tscn
##
## Not a gated verification, deliberately. Every number it prints depends on
## three balance constants §2.1 itself calls "a balancing number, not a design
## decision" — SPAWN_RATE_PER_DAY, EXPORT_MAX_DISTANCE_FROM_PLAYER and
## MAX_EXPORTS_PER_DAY — plus the baked population capacity under them. Asserting
## any of it would freeze a tuning knob into the gate. This exists so the person
## turning those knobs can see what they do.
##
## It boots the real Main.tscn (several minutes of map generation, per
## verify_gates.gd's own note) and then advances the day counter by hand rather
## than waiting 40 real minutes per in-game day.
##
## **Read the export column with that in mind.** Calling run_daily_tick() in a
## loop means no frames pass, so HordeManager never moves anything: an exported
## horde stays parked on the hex it came from, still counted in that hex's own
## `zombie_count`, so the hex reads as full and ships again the next "day" until
## its residents hit the 75% floor. In real play the horde walks off and the
## hex's total falls with it. The per-day sizes here are therefore an upper
## bound on how long one hex keeps shipping, not a prediction of it.

const _DAYS: int = 60

var _main: Node


func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_report(hex_grid_map)
	else:
		hex_grid_map.generation_completed.connect(func(_count: int) -> void: _report(hex_grid_map))


func _report(hex_grid_map: HexGridMap) -> void:
	var infestation: InfestationManager = _main.get_node("InfestationManager")
	var hordes: HordeManager = _main.get_node("HordeManager")
	var buildings: BuildingManager = _main.get_node("BuildingManager")
	var start_hexes := buildings.get_starting_settlement_hexes()
	var start: Vector2i = start_hexes[0] if not start_hexes.is_empty() else Vector2i.ZERO

	print("=== Opening state (D7's rings from %s) ===" % start)
	_print_band_histogram(hex_grid_map, infestation)

	print("\n=== Capacity around the start ===")
	for ring in range(0, 7):
		var coord := start + Vector2i(ring, 0)
		print("  ring %d %s: capacity %d, %.1f%% infested" % [
			ring, coord, infestation.capacity_at(coord), infestation.infestation_at(coord)])

	print("\n=== %d days, no player action ===" % _DAYS)
	var horde_count_before := hordes.get_all_hordes().size()
	var exported_total := 0
	var largest := 0
	for day in range(_DAYS):
		var before := hordes.get_all_hordes().size()
		var sizes_before := _total_horde_size(hordes)
		infestation.run_daily_tick()
		var shipped := _total_horde_size(hordes) - sizes_before
		exported_total += maxi(0, shipped)
		largest = maxi(largest, shipped)
		if shipped > 0:
			print("  day %2d: exported %d zombies (%d hordes on the map)" % [
				day + 1, shipped, hordes.get_all_hordes().size()])
		elif hordes.get_all_hordes().size() != before:
			print("  day %2d: horde count changed with no export" % [day + 1])

	print("\n  hordes before %d, after %d" % [horde_count_before, hordes.get_all_hordes().size()])
	print("  exported %d zombies over %d days, largest single export %d" % [exported_total, _DAYS, largest])
	print("\n=== Band histogram after %d days ===" % _DAYS)
	_print_band_histogram(hex_grid_map, infestation)
	get_tree().quit(0)


func _print_band_histogram(hex_grid_map: HexGridMap, infestation: InfestationManager) -> void:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	var land := 0
	var total := 0
	for cell: HexCell in hex_grid_map.get_all_cells():
		if cell.biome_type == GameEnums.BiomeType.OCEAN:
			continue
		land += 1
		total += infestation.zombie_count_at(cell.coord)
		counts[int(infestation.band_at(cell.coord))] += 1
	var names := ["Cleared", "Fringe", "Contested", "Hive Core"]
	for band in range(4):
		print("  %-10s %5d hexes (%.1f%%)" % [names[band], counts[band], 100.0 * float(counts[band]) / maxf(1.0, float(land))])
	print("  %d land hexes, %d zombies on the map" % [land, total])


func _total_horde_size(hordes: HordeManager) -> int:
	var total := 0
	for horde: Horde in hordes.get_all_hordes():
		total += horde.size
	return total
