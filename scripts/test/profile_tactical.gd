extends Node

## Where Tactical-view frame time actually goes. Run (NOT --headless — a
## headless viewport renders nothing, so the whole question is invisible to it,
## the same constraint smoke_screenshot.gd and verify_save_screenshot.gd
## record):
##
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/profile_tactical.tscn
##
## Reports two things, in this order, because the second is only meaningful
## once the first says there is a problem to attribute:
##
## 1. **A frame-time profile at each zoom band**, with Godot's own counters
##    beside it — script time, physics time, draw calls, rendered primitives,
##    node count. Tactical is three different renderers either side of
##    CameraController's thresholds, so "the game is slow in Tactical" can mean
##    three unrelated things and the band has to be named.
## 2. **An ABLATION**: disable one subsystem, re-measure the same frames, and
##    report the delta. Cheaper and far more honest than instrumenting each
##    _process() by hand — it measures the whole end-to-end cost of a system
##    including whatever it makes the RENDERER do, which per-function script
##    timing cannot see and which is where a MultiMesh or a mesh chunk actually
##    spends. `set_process(false)` plus `visible = false` is a real ablation
##    for these nodes; each one is either a data source polled per frame or a
##    CanvasItem, and none is load-bearing for another's per-frame work within
##    one sample window.
##
## Percentiles, not means. A mean hides exactly the defect a player reports as
## "laggy" — a 90 ms hitch every twentieth frame reads as 8 ms averaged, and
## streamed terrain and mesh chunk builds are hitch-shaped by construction
## (TerrainDetailView builds CHUNKS_BUILT_PER_FRAME per frame; ReliefTileView
## loads TILES_LOADED_PER_FRAME).
##
## Nothing here asserts. It is a diagnostic: the numbers decide what to
## optimise, and a gate written before the numbers exist would gate the wrong
## thing.

const _WINDOW_SIZE := Vector2i(1280, 720)

## Straddles the bands smoke_screenshot.gd already establishes. 05 is the one a
## player reaching for "very very slow" is most likely in — past
## high_fidelity_threshold, where individual zombies draw at all — but the two
## below it are measured because a regression at 0.23 and a regression at 2.6
## have nothing to do with each other.
const _BANDS: Array[Dictionary] = [
	{"name": "tactical_entry", "zoom": 0.230, "offset": Vector2i.ZERO},
	{"name": "tactical_close", "zoom": 1.300, "offset": Vector2i.ZERO},
	{"name": "tactical_crowd", "zoom": 2.600, "offset": Vector2i(1, 0)},
]

## Long enough for relief streaming and mesh chunk building to settle, so the
## sample measures a STEADY state rather than the load burst. smoke_screenshot
## uses 200/320 for the same reason.
const _WARMUP_FRAMES: int = 260
const _FIRST_WARMUP_FRAMES: int = 340
const _SAMPLE_FRAMES: int = 120

## Every node in Main.tscn whose script defines _process or _physics_process,
## enumerated from the source rather than picked by suspicion. The first
## version of this list was picked by suspicion and missed five of them —
## UnitOrderController, ResidentDefenseController, UnitCommandController,
## WallPlacementController and AgentHarness — which is exactly how a sweep
## comes back saying nothing accounts for the cost.
##
## CanvasItems with only a _draw() (ElevationReliefView, StrategicOverlayManager,
## CoastlineOutlineView, MinimapView inside MainHUD) are here too: hiding a
## CanvasItem stops its redraw, which is the cost that matters for them.
const _ABLATIONS: Array[Dictionary] = [
	{"name": "UnitOrderController", "path": "UnitOrderController"},
	{"name": "ResidentDefenseController", "path": "ResidentDefenseController"},
	{"name": "ZombieSwarmManager", "path": "ZombieSwarmManager"},
	{"name": "TacticalEntityLayer", "path": "WorldRoot/TacticalEntityLayer"},
	{"name": "HordeManager", "path": "HordeManager"},
	{"name": "UnitManager", "path": "UnitManager"},
	{"name": "LiveHexTracker", "path": "LiveHexTracker"},
	{"name": "LocalDetailManager", "path": "WorldRoot/LocalDetailManager"},
	{"name": "TerrainDetailView", "path": "WorldRoot/TerrainDetailView"},
	{"name": "TerrainMeshView", "path": "WorldRoot/TerrainMeshView"},
	{"name": "ReliefTileView", "path": "WorldRoot/ReliefTileView"},
	{"name": "ElevationReliefView", "path": "WorldRoot/ElevationReliefView"},
	{"name": "CoastlineOutlineView", "path": "WorldRoot/CoastlineOutlineView"},
	{"name": "StrategicOverlayManager", "path": "WorldRoot/StrategicOverlayManager"},
	{"name": "UnitCommandController", "path": "WorldRoot/UnitCommandController"},
	{"name": "WallPlacementController", "path": "WorldRoot/WallPlacementController"},
	{"name": "BuildPlacementController", "path": "WorldRoot/BuildPlacementController"},
	{"name": "FogOfWarManager", "path": "FogOfWarManager"},
	{"name": "AgentHarness", "path": "AgentHarness"},
	{"name": "MainHUD", "path": "MainHUD"},
	{"name": "SeaView", "path": "WorldRoot/SeaView"},
]

## The band the ablation sweep runs in. One band, because a full sweep is
## _ABLATIONS.size() * (_WARMUP + _SAMPLE) frames and doing all three would run
## for many minutes; the crowd band is where the report came from.
const _ABLATION_BAND: int = 2

var _main: Node
var _camera: CameraController
var _focus: Vector2i


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: run this windowed, not --headless — a headless viewport renders nothing, so there is no frame cost to measure.")
		get_tree().quit(1)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_WINDOW_SIZE)
	# Uncapped: a profile against a 60 Hz vsync ceiling reports 16.7 ms for
	# everything that is merely fast enough, and says nothing about headroom.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_on_map_ready()
	else:
		hex_grid_map.generation_completed.connect(_on_map_ready)


func _on_map_ready() -> void:
	var building_manager: BuildingManager = _main.get_node("BuildingManager")
	var start_hexes: Array[Vector2i] = building_manager.get_starting_settlement_hexes()
	if start_hexes.is_empty():
		print("FAIL: no starting settlement to frame.")
		get_tree().quit(1)
		return
	_focus = start_hexes[0]

	_camera = _main.get_node("CameraController")
	# Same input immunity smoke_screenshot.gd documents: _process() edge/key-pans,
	# _input() middle-drags and _unhandled_input() zooms on the wheel, all from
	# whatever the desktop sends this window while it sits open for minutes. A
	# stray mouse wheel mid-run would silently reprofile a different band.
	_camera.edge_pan_enabled = false
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()

	await _run()
	get_tree().quit(0)


func _run() -> void:
	print("Profiling from starting settlement %s at %dx%d, vsync off\n" % [
		_focus, _WINDOW_SIZE.x, _WINDOW_SIZE.y])

	print("=== Frame cost by zoom band ===")
	print("%-16s %8s %8s %8s %8s %10s %10s %8s" % [
		"band", "med ms", "p95 ms", "max ms", "fps", "draws", "prims", "nodes"])
	for i in _BANDS.size():
		var band: Dictionary = _BANDS[i]
		await _frame_band(band, _FIRST_WARMUP_FRAMES if i == 0 else _WARMUP_FRAMES)
		var sample := await _sample()
		_print_band(band["name"], sample)

	_census()
	await _run_ablation()


## Disables one subsystem at a time and reports what the frame gets back.
##
## Two things the first version of this got wrong, both visible in its own
## output and both fixed here:
##
## - **It measured the baseline once, at the start.** Several rows then came
##   back NEGATIVE — disabling a system apparently made the frame slower by up
##   to 10% — which is drift, not physics. The baseline is now re-measured
##   either side of every ablation and the two averaged, so slow drift over a
##   multi-minute sweep cancels instead of accumulating into the deltas.
## - **MIN, not just median.** Under any external load (another Godot instance,
##   a browser, an indexer) the median absorbs whatever the machine was doing;
##   the minimum frame in a window is the closest thing to an uncontended
##   measurement this harness can get. Where min and median disagree sharply,
##   the machine was busy and the run should be repeated.
##
## The ALL-OFF row is the load-bearing one. If disabling every ablatable node
## still leaves the frame expensive, the cost is not in any of them — it is in
## an autoload, in the renderer, or in this harness — and no amount of staring
## at individual rows will find it.
func _run_ablation() -> void:
	var band: Dictionary = _BANDS[_ABLATION_BAND]
	print("\n=== Ablation in the %s band (zoom %.2f) ===" % [band["name"], band["zoom"]])
	await _frame_band(band, _WARMUP_FRAMES)

	print("%-26s %8s %8s %9s %8s %8s" % ["disabled", "med ms", "min ms", "d(med)", "d(min)", "% med"])
	var first := await _sample()
	print("%-26s %8.2f %8.2f %9s %8s %8s" % ["(nothing — baseline)", first["median"], first["min"], "—", "—", "—"])

	for entry in _ABLATIONS:
		var node := _main.get_node_or_null(entry["path"])
		if node == null:
			print("%-26s %8s  (no such node at %s)" % [entry["name"], "skip", entry["path"]])
			continue
		var before := await _sample()
		var restore := _disable(node)
		var off := await _sample()
		_restore(node, restore)
		var after := await _sample()
		_report_row(entry["name"], (before["median"] + after["median"]) * 0.5,
			(before["min"] + after["min"]) * 0.5, off)

	# Everything at once. The one row that says whether the list is even
	# looking in the right place.
	var before_all := await _sample()
	var restores: Array = []
	for entry in _ABLATIONS:
		var node := _main.get_node_or_null(entry["path"])
		if node != null:
			restores.append([node, _disable(node)])
	for _f in 60:
		await get_tree().process_frame
	var all_off := await _sample()
	for pair in restores:
		_restore(pair[0], pair[1])
	for _f in 60:
		await get_tree().process_frame
	var after_all := await _sample()
	_report_row("ALL OF THE ABOVE", (before_all["median"] + after_all["median"]) * 0.5,
		(before_all["min"] + after_all["min"]) * 0.5, all_off)

	print("\nRead the ALL OF THE ABOVE row first. What it does NOT account for is")
	print("autoloads (TickManager, TimeCycleManager), the renderer, and this harness.")


## `node is CanvasItem` is NOT the right test and getting it wrong cost a whole
## sweep: MainHUD is a **CanvasLayer**, which carries `visible` but does not
## inherit from CanvasItem. The first run therefore never hid it, only stopped
## its _process, and reported the single most expensive node in the game at
## -0.17 ms. Ask whether the property exists instead of guessing the class.
func _disable(node: Node) -> Dictionary:
	var hideable: bool = "visible" in node
	var state := {
		"process": node.is_processing(),
		"physics": node.is_physics_processing(),
		"hideable": hideable,
		"visible": node.get("visible") if hideable else true,
	}
	node.set_process(false)
	node.set_physics_process(false)
	if hideable:
		node.set("visible", false)
	return state


func _restore(node: Node, state: Dictionary) -> void:
	node.set_process(state["process"])
	node.set_physics_process(state["physics"])
	if state["hideable"]:
		node.set("visible", state["visible"])


func _report_row(name: String, base_median: float, base_min: float, off: Dictionary) -> void:
	var d_med: float = base_median - off["median"]
	print("%-26s %8.2f %8.2f %9.2f %8.2f %7.1f%%" % [
		name, off["median"], off["min"], d_med, base_min - off["min"],
		100.0 * d_med / maxf(base_median, 0.001)])


## Where the scene tree's nodes actually are. The first run reported 19,648
## nodes and barely moved between zoom bands, which is not what a streamed
## renderer should look like — so this names the owners rather than leaving it
## as one number. Godot walks every node with processing enabled once per
## frame and notifies every CanvasItem on redraw, so a five-figure count is a
## per-frame cost in itself, independent of what any one node does.
func _census() -> void:
	print("
=== Scene tree census (descendants per subsystem) ===")
	var rows: Array = []
	for entry in _ABLATIONS:
		var node := _main.get_node_or_null(entry["path"])
		if node != null:
			rows.append([entry["name"], _descendants(node)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var counted := 0
	for row in rows:
		if row[1] > 0:
			print("  %-28s %7d" % [row[0], row[1]])
		counted += row[1]
	print("  %-28s %7d" % ["(everything else)", _descendants(_main) - counted])
	print("  %-28s %7d" % ["TOTAL under Main", _descendants(_main)])


func _descendants(node: Node) -> int:
	var total := node.get_child_count()
	for child in node.get_children():
		total += _descendants(child)
	return total


func _frame_band(band: Dictionary, warmup: int) -> void:
	var framed: Vector2i = _focus + (band.get("offset", Vector2i.ZERO) as Vector2i)
	var target := HexCoord.axial_to_world(framed)
	_camera.global_position = target
	## set_zoom_level(), not `zoom =` — that skips the tactical_mode_changed /
	## tactical_fidelity_changed signals LocalDetailManager and
	## TacticalEntityLayer hydrate off, so the band would render as the previous
	## one while claiming to be this one.
	_camera.set_zoom_level(band["zoom"])
	for _f in warmup:
		Engine.max_fps = 0
		await get_tree().process_frame
	# Re-assert rather than trust it survived, same discipline the screenshot
	# scripts carry.
	_camera.global_position = target
	_camera.set_zoom_level(band["zoom"])
	await get_tree().process_frame


## One sample window of real frame deltas plus Godot's own counters. Uses
## Time.get_ticks_usec() around the awaited frame rather than `delta`, which is
## the frame time the engine REPORTS and is clamped by Engine.max_fps and by
## physics interpolation.
func _sample() -> Dictionary:
	var frames: Array[float] = []
	var draws := 0.0
	var prims := 0.0
	var script_ms := 0.0
	for _f in _SAMPLE_FRAMES:
		Engine.max_fps = 0  # BackgroundExecutionManager pins this to 15 whenever the window is unfocused.
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	frames.sort()
	var n := frames.size()
	return {
		"median": frames[n / 2],
		"min": frames[0],
		"p95": frames[mini(n - 1, int(float(n) * 0.95))],
		"max": frames[n - 1],
		"draws": draws / float(n),
		"prims": prims / float(n),
		"script_ms": script_ms / float(n),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


func _print_band(name: String, s: Dictionary) -> void:
	print("%-16s %8.2f %8.2f %8.2f %8.1f %10.0f %10.0f %8.0f" % [
		name, s["median"], s["p95"], s["max"], 1000.0 / maxf(s["median"], 0.001),
		s["draws"], s["prims"], s["nodes"]])
	# Godot's own TIME_PROCESS counter, printed beside the wall-clock frame
	# rather than as a share of it: the two are sampled at different points in
	# the frame and TIME_PROCESS came back LARGER than the measured frame in
	# the first run, so it is a corroborating signal, not a subdivision.
	print("%-16s   min %.2f ms; Godot's own TIME_PROCESS counter: %.2f ms" % [
		"", s["min"], s["script_ms"]])
