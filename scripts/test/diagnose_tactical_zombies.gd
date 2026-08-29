extends Node

## What §2.1's tactical layer actually instantiates on the REAL map, rather
## than on verify_tactical_zombies.gd's flat fixture. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_tactical_zombies.tscn
##
## Not a gated verification, deliberately. Every number below is a function of
## ZombieSwarmManager.ENTITY_BUDGET and HORDE_BUDGET_FRACTION, which are
## budget knobs rather than rules, and of the baked population capacity under
## them. Asserting any of it would freeze a tuning knob into the gate. This
## exists so the person turning those knobs can see what they do, and so
## §2.1's own claim — "in London that is ~60,000 real zombies with ~1.84
## million more behind them" — is a measurement rather than an estimate.
##
## It boots the real Main.tscn (several minutes of map generation, per
## verify_gates.gd's own note) and then drives the camera by hand rather than
## waiting for a player to pan there.
##
## Two things it cannot show, both stated so the output is not over-read.
## Rendering is absent: this is headless, and headless backs no MultiMesh
## storage at all, so what a crowd LOOKS like is a windowed question
## (CLAUDE.md §0.1). And the per-step cost printed here is the tactical
## layer's alone, measured on a machine also generating the map moments
## earlier — bench_zombie_swarm.gd is the isolated number.

## Where to point the camera. The starting settlement, then the three cities
## the population bake places by hand (decisions.md D35), which are the densest
## ground on the map and therefore the worst case for the budget.
const _CITY_NAMES: Array[String] = ["Manchester", "Birmingham", "Greater London"]

const _STEP_SAMPLES: int = 60

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
	var camera: CameraController = _main.get_node("CameraController")
	var tracker: LiveHexTracker = _main.get_node("LiveHexTracker")
	var swarms: ZombieSwarmManager = _main.get_node("ZombieSwarmManager")
	var infestation: InfestationManager = _main.get_node("InfestationManager")
	var buildings: BuildingManager = _main.get_node("BuildingManager")

	print("=== Budget ===")
	print("  ENTITY_BUDGET %d, hordes reserved %d, slice target %d, max slices %d"
			% [ZombieSwarmManager.ENTITY_BUDGET,
			int(ZombieSwarmManager.ENTITY_BUDGET * ZombieSwarmManager.HORDE_BUDGET_FRACTION),
			ZombieSwarm.SLICE_TARGET_ENTITIES, ZombieSwarm.MAX_SLICES])

	print("\n=== Strategic zoom (the default) ===")
	camera.zoom = Vector2.ONE * (camera.tactical_zoom_threshold * 0.5)
	tracker.refresh()
	swarms.allocate()
	print("  %d live hexes, %d individuals — nothing can draw them from out here"
			% [tracker.get_live_hexes().size(), swarms.get_entity_count()])

	var targets: Array[Vector2i] = []
	var labels: Array[String] = []
	var start_hexes := buildings.get_starting_settlement_hexes()
	if not start_hexes.is_empty():
		targets.append(start_hexes[0])
		labels.append("starting settlement")
	for city_name in _CITY_NAMES:
		var coord := _densest_hex_of(city_name, infestation)
		if coord != Vector2i.MAX:
			targets.append(coord)
			labels.append(city_name)

	print("\n=== Tactical zoom, camera hex by camera hex ===")
	print("  %-26s %9s %8s %9s %9s %7s" % ["where", "on hex", "live", "wanted", "drawn", "groups"])
	for i in targets.size():
		var coord := targets[i]
		camera.global_position = HexCoord.axial_to_world(coord)
		camera.zoom = Vector2.ONE * 4.0
		tracker.refresh()
		swarms.allocate()
		var live := tracker.get_live_hexes()
		var wanted := 0
		for live_coord in live:
			wanted += infestation.zombie_count_at(live_coord)
		print("  %-26s %9d %8d %9d %9d %7d" % [
			labels[i], infestation.zombie_count_at(coord), live.size(),
			wanted, swarms.get_entity_count(), swarms.get_group_count()])
		if wanted > swarms.get_entity_count():
			print("      %s behind the %d drawn" % [wanted - swarms.get_entity_count(), swarms.get_entity_count()])

	print("\n=== Step cost where the crowd is biggest ===")
	var worst := targets[targets.size() - 1] if not targets.is_empty() else Vector2i.ZERO
	camera.global_position = HexCoord.axial_to_world(worst)
	camera.zoom = Vector2.ONE * 4.0
	tracker.refresh()
	swarms.allocate()
	var samples: Array[float] = []
	for i in _STEP_SAMPLES:
		var t0 := Time.get_ticks_usec()
		swarms.step(1.0 / 60.0)
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	print("  %d individuals in %d groups: %.2f ms/step (median of %d)"
			% [swarms.get_entity_count(), swarms.get_group_count(),
			samples[samples.size() / 2], _STEP_SAMPLES])

	print("\n=== Save size (D15) ===")
	var state := swarms.get_save_state()
	var floats := 0
	for coord: Vector2i in state:
		floats += (state[coord] as PackedFloat32Array).size()
	print("  %d hexes, %d floats, %.1f KB" % [state.size(), floats, float(floats * 4) / 1024.0])
	get_tree().quit(0)


## The busiest hex of a named settlement footprint, not its first — a city
## spans several hexes and only one of them carries the bulk of the population
## the bake put there (decisions.md D35).
##
## Vector2i.MAX means "this map has no such named feature", which is a real
## possibility rather than an error: the footprints are seed data and a future
## map could drop one.
func _densest_hex_of(feature_name: String, infestation: InfestationManager) -> Vector2i:
	var best := Vector2i.MAX
	var best_count := -1
	for feature in BritishGeographyData.get_features():
		if feature.feature_name != feature_name:
			continue
		for coord in feature.hex_coords:
			var count := infestation.zombie_count_at(coord)
			if count > best_count:
				best_count = count
				best = coord
	return best
