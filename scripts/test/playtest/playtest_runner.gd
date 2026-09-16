extends Node

## Deterministic playtest scenarios against the real Main.tscn. Answers "did this
## change improve the player's experience?" with evidence: telemetry
## (scripts/telemetry/GameplayTelemetry.gd), each scenario's own experience
## checks, and — windowed only — screenshots at the scenario's checkpoints.
##
## Run one scenario (user args go after `--`):
##
##   Godot_console.exe --headless res://scenes/test/playtest_runner.tscn -- --scenario=opening
##   Godot_console.exe res://scenes/test/playtest_runner.tscn -- --scenario=siege --shots
##
## or all of them through tools/playtest/run_scenarios.py, which also collects the
## JSON. Options: --scenario=NAME, --days=N (override), --variant=NAME (scenario
## specific), --out=ABSOLUTE_PATH.json, --shots (windowed; ignored headless),
## --with-props (keep terrain-detail props as steering obstacles; see _ready()).
##
## A --shots run is not numerically comparable with a headless one: it keeps terrain
## props and lets real frames run during each checkpoint (the render-only views need
## them). Measured 2026-09-16: the same siege scenario produced a breach headless and
## no contact at all windowed. Compare headless with headless.
##
## Not a gate. Exit code is 0 when the scenario RAN, whatever it measured —
## PLAYER_EXPERIENCE.md's acceptance criteria are judged by reading the output,
## and a boring scenario is a finding, not a failure. Exit 1 means the harness
## itself broke (unknown scenario, no starting settlement).
##
## Time is hand-driven at a fixed delta for the reason diagnose_horde_contact.gd
## records (decisions.md D75): headless never focuses the window, so
## BackgroundExecutionManager pins max_fps to 15 and a real-frame loop runs at
## wall-clock pace, and real deltas are not reproducible. The per-frame managers
## driven below are every gameplay class with a _process() that advances
## simulation; render-only views (TacticalEntityLayer, LiveHexTracker,
## ZombieSwarmManager, terrain streaming) are left to real frames, which only
## happen during a screenshot checkpoint.

const _SCENARIOS := {
	"opening": preload("res://scripts/test/playtest/scenarios/opening.gd"),
	"expansion": preload("res://scripts/test/playtest/scenarios/expansion.gd"),
	"horde": preload("res://scripts/test/playtest/scenarios/horde.gd"),
	"siege": preload("res://scripts/test/playtest/scenarios/siege.gd"),
	"industrialisation": preload("res://scripts/test/playtest/scenarios/industrialisation.gd"),
	"vertical_slice": preload("res://scripts/test/playtest/scenarios/vertical_slice.gd"),
}
const _Telemetry := preload("res://scripts/telemetry/GameplayTelemetry.gd")

## 5.0 s puts a horde about a quarter of a hex per step at BASE_MOVE_SPEED;
## same value and reason as diagnose_horde_contact.gd.
const STEP_SECONDS: float = 5.0
const _SHOT_WARMUP_FRAMES: int = 120
const _SHOT_ZOOMS: Array[float] = [0.11, 1.3, 60.0]  ## Colony overview, tactical, battle scale — smoke_screenshot.gd's framings 02/04/06.

var main: Node
var buildings: BuildingManager
var units: UnitManager
var orders: UnitOrderController
var hordes: HordeManager
var infestation: InfestationManager
var resources: ResourceManager
var tech: TechManager
var walls: WallManager
var fog: FogOfWarManager
var residents: ResidentDefenseController
var wall_defense: WallDefenseController
var slice_director: VerticalSliceDirector
var telemetry: Node
var start_hex: Vector2i
var variant: String = ""

var _scenario_name: String = "opening"
var _scenario: RefCounted
var _days_override: int = -1
var _out_path: String = ""
var _shots: bool = false
var _notes: Array[String] = []
var _shot_paths: Array[String] = []
var _cost_usec: Dictionary = {}
var _with_props: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario_name = arg.get_slice("=", 1)
		elif arg.begins_with("--days="):
			_days_override = int(arg.get_slice("=", 1))
		elif arg.begins_with("--variant="):
			variant = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out_path = arg.get_slice("=", 1)
		elif arg == "--with-props":
			_with_props = true
		elif arg == "--shots":
			_shots = DisplayServer.get_name() != "headless"
	if not _SCENARIOS.has(_scenario_name):
		print("PLAYTEST ERROR: unknown scenario '%s'. Known: %s" % [_scenario_name, ", ".join(_SCENARIOS.keys())])
		get_tree().quit(1)
		return
	_scenario = _SCENARIOS[_scenario_name].new()
	if _scenario.has_method("launch_vertical_slice") and _scenario.launch_vertical_slice():
		GameLaunchState.request_vertical_slice()

	main = load("res://scenes/main/Main.tscn").instantiate()
	if not _with_props and not _shots:  ## Screenshots need the props on screen.
		# Without this a unit walking through streamed terrain detail costs ~220 ms
		# per unit per movement call (measured 2026-09-16: 214 s for one simulated
		# day with two units), because UnitOrderController._gather_obstacles() builds
		# a Dictionary for every prop in two whole hexes on every call. Removing the
		# view before _ready() leaves LocalDetailManager's path unresolved, which its
		# own doc comment defines as "no obstacles" — how movement already behaves in
		# any hex whose detail is not streamed. Pass --with-props to keep them.
		var detail := main.get_node("WorldRoot/TerrainDetailView")
		detail.get_parent().remove_child(detail)
		detail.free()
	add_child(main)
	var hex_grid_map: HexGridMap = main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_run()
	else:
		hex_grid_map.generation_completed.connect(func(_count: int) -> void: _run())


func _run() -> void:
	buildings = main.get_node("BuildingManager")
	units = main.get_node("UnitManager")
	orders = main.get_node("UnitOrderController")
	hordes = main.get_node("HordeManager")
	infestation = main.get_node("InfestationManager")
	resources = main.get_node("ResourceManager")
	tech = main.get_node("TechManager")
	walls = main.get_node("WallManager")
	fog = main.get_node("FogOfWarManager")
	residents = main.get_node("ResidentDefenseController")
	wall_defense = main.get_node("WallDefenseController")
	slice_director = main.get_node("VerticalSliceDirector")

	var start_hexes := buildings.get_starting_settlement_hexes()
	if start_hexes.is_empty():
		print("PLAYTEST ERROR: no starting settlement.")
		get_tree().quit(1)
		return
	start_hex = start_hexes[0]

	# AlertManager auto-pauses on every WARNING+ event. Time here is driven by
	# hand, so a pause changes nothing but Engine.time_scale; set it anyway so a
	# screenshot checkpoint's real frames cannot advance the simulation.
	TickManager.set_speed_index(0)

	telemetry = _Telemetry.new()
	add_child(telemetry)
	telemetry.attach(main)

	var days: int = _days_override if _days_override > 0 else _scenario.days()
	var checkpoints: Array = _scenario.checkpoints() if _shots else []
	print("PLAYTEST %s%s: %d days from %s" % [_scenario_name, (" [" + variant + "]") if variant else "", days, start_hex])
	_scenario.setup(self)
	if checkpoints.has(0):
		await _capture("day00")

	var steps_per_day := int(TickManager.DAY_LENGTH_SECONDS / STEP_SECONDS)
	for day in range(days):
		var day_started_ms := Time.get_ticks_msec()
		for step in range(steps_per_day):
			advance(STEP_SECONDS)
			_scenario.on_step(self, step)
		_scenario.on_day(self, TickManager.current_day)
		_progress("day %d/%d done in %d ms wall, %d living units, %d hordes [%s]" % [
			day + 1, days, Time.get_ticks_msec() - day_started_ms, living_units().size(), hordes.get_all_hordes().size(), _cost_summary()])
		if checkpoints.has(day + 1):
			await _capture("day%02d" % (day + 1))

	var result := {
		"scenario": _scenario_name,
		"variant": variant,
		"start_hex": str(start_hex),
		"days": days,
		"step_seconds": STEP_SECONDS,
		"terrain_props_as_obstacles": _with_props,
		"experience_checks": _scenario.assess(self),
		"notes": _notes,
		"screenshots": _shot_paths,
		"telemetry": telemetry.report(),
	}
	_write(result)
	get_tree().quit(0)


## One fixed simulation step through every per-frame gameplay manager. Each call
## is timed into _cost_usec so a slow scenario says which manager it is waiting on.
func advance(seconds: float) -> void:
	var t := Time.get_ticks_usec()
	TickManager._process(seconds)
	TimeCycleManager._process(seconds)
	t = _charge("ticks", t)
	hordes._process(seconds)
	t = _charge("hordes", t)
	orders._process(seconds)
	t = _charge("unit_orders", t)
	residents._process(seconds)
	t = _charge("residents", t)
	wall_defense._process(seconds)
	t = _charge("wall_defense", t)
	slice_director._process(seconds)
	t = _charge("slice", t)
	fog._process(seconds)
	t = _charge("fog", t)
	telemetry.observe_hordes()
	_charge("telemetry", t)


func _charge(key: String, since_usec: int) -> int:
	var now := Time.get_ticks_usec()
	_cost_usec[key] = int(_cost_usec.get(key, 0)) + (now - since_usec)
	return now


func _cost_summary() -> String:
	var parts: Array[String] = []
	for key in _cost_usec:
		parts.append("%s %d ms" % [key, int(_cost_usec[key]) / 1000])
	_cost_usec.clear()
	return ", ".join(parts)


## Flushed to user://playtest/progress.txt every day, because Godot block-buffers a
## redirected stdout and a slow run otherwise looks identical to a hung one.
func _progress(line: String) -> void:
	print(line)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://playtest"))
	var file := FileAccess.open("user://playtest/progress.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://playtest/progress.txt") else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line("%s %s: %s" % [_scenario_name, variant, line])
		file.close()


func note(line: String) -> void:
	_notes.append("day %d: %s" % [TickManager.current_day, line])
	print("  " + _notes[-1])


## Tries the hex centre, then a spiral of offsets, because placement is decided
## per 30 m sub-cell and the centre of a settlement hex is often the wrong biome.
func place(building_type: GameEnums.BuildingType, coord: Vector2i) -> bool:
	var last_error := ""
	for radius in [0.0, 60.0, 120.0, 200.0, 300.0]:
		for i in range(12 if radius > 0.0 else 1):
			var offset := Vector2.from_angle(TAU * float(i) / 12.0) * float(radius)
			last_error = buildings.get_placement_error(building_type, coord, offset)
			if last_error.is_empty():
				return buildings.place_building(building_type, coord, offset)
	note("could not place %s at %s: %s" % [BuildingCatalog.get_definition(building_type).display_name, coord, last_error])
	return false


func train(unit_type: GameEnums.UnitType, count: int) -> int:
	var trainer := _trainer_coord_for(unit_type)
	var started := 0
	for i in range(count):
		if units.train_unit(unit_type, trainer):
			started += 1
		else:
			note("could not train %s: %s" % [UnitCatalog.get_definition(unit_type).display_name, units.get_training_error(unit_type, trainer)])
			break
	return started


func living_units() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for unit: UnitInstance in units.get_all_units():
		if not unit.is_destroyed():
			out.append(unit)
	return out


func attack_move_all(destination: Vector2i) -> void:
	for unit in living_units():
		orders.issue_attack_move_order(unit, destination)


func grant(amounts: Dictionary) -> void:
	for resource_type in amounts:
		resources.add(resource_type, float(amounts[resource_type]))


## A land hex at exactly `distance` from the start that a unit can actually route
## to, preferring the most (or least) populated one so scenarios hit a real threat,
## not moorland. Unreachable candidates are noted: measured 2026-09-16, an attack-move
## at an unroutable hex re-runs a failed HexPathfinder search (~234 ms each) every
## UnitOrderController.REPLAN_RETRY_SECONDS, which stalled the first opening run.
## `require_route` false is for horde spawns, which do not need a unit path.
func hex_at_distance(distance: int, most_populated: bool = true, require_route: bool = true) -> Vector2i:
	var best := start_hex
	var best_capacity := -1
	var hex_grid_map: HexGridMap = main.get_node("WorldRoot/HexGridMap")
	var logistics: LogisticsNetwork = main.get_node("LogisticsNetwork")
	var unreachable: Array[String] = []
	for coord in HexCoord.hex_ring(start_hex, distance):
		var cell := hex_grid_map.get_cell(coord)
		if cell == null or not cell.is_passable():
			continue
		if require_route and HexPathfinder.find_path(hex_grid_map, start_hex, coord, logistics, walls, true).size() < 2:
			unreachable.append(str(coord))
			continue
		var capacity := infestation.capacity_at(coord)
		var better := capacity > best_capacity if most_populated else (best_capacity < 0 or capacity < best_capacity)
		if better:
			best = coord
			best_capacity = capacity
	if not unreachable.is_empty():
		note("%d passable hexes at distance %d have no unit route from the start: %s" % [unreachable.size(), distance, ", ".join(unreachable)])
	if best == start_hex:
		note("no routable hex at distance %d; scenario targets fall back to the start hex" % distance)
	return best


func spawn_horde(coord: Vector2i, size: int) -> Horde:
	hordes.spawn_horde_at(coord, size)
	var spawned: Horde = null
	for horde: Horde in hordes.get_hordes_at(coord):
		if spawned == null or horde.id > spawned.id:
			spawned = horde
	return spawned


func _trainer_coord_for(unit_type: GameEnums.UnitType) -> Vector2i:
	for building: BuildingInstance in buildings.get_all_buildings():
		if building.is_ruined or building.is_under_construction:
			continue
		if units.get_training_error(unit_type, building.hex_coord).is_empty():
			return building.hex_coord
	return start_hex


func _capture(label: String) -> void:
	var camera: CameraController = main.get_node("CameraController")
	camera.edge_pan_enabled = false
	camera.set_process(false)
	camera.set_process_input(false)
	camera.set_process_unhandled_input(false)
	camera.make_current()
	var dir := "user://playtest_shots/%s%s" % [_scenario_name, ("_" + variant) if variant else ""]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for zoom in _SHOT_ZOOMS:
		var focus: Vector2 = _scenario.camera_focus(self)
		camera.global_position = focus
		camera.set_zoom_level(zoom)
		for _f in _SHOT_WARMUP_FRAMES:
			await get_tree().process_frame
		camera.global_position = focus
		camera.set_zoom_level(zoom)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_zoom%s.png" % [dir, label, str(zoom).replace(".", "_")]
		get_viewport().get_texture().get_image().save_png(path)
		_shot_paths.append(ProjectSettings.globalize_path(path))


func _write(result: Dictionary) -> void:
	var text := JSON.stringify(result, "  ")
	var path := _out_path if not _out_path.is_empty() else "user://playtest/%s%s.json" % [_scenario_name, ("_" + variant) if variant else ""]
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
		print("PLAYTEST RESULT written to %s" % (ProjectSettings.globalize_path(path) if path.begins_with("user://") else path))
	print("PLAYTEST CHECKS %s" % JSON.stringify(result["experience_checks"]))
