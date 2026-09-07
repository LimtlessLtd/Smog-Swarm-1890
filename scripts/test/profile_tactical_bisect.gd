extends Node

## Coarse bisection of Tactical frame cost, after a fine-grained ablation
## failed to find it. Run (NOT --headless):
##
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/profile_tactical_bisect.tscn
##
## ## Why this exists
##
## profile_tactical.gd disabled every node in Main.tscn that defines _process
## or _physics_process, one at a time and then all together, and recovered
## **4.40 ms of a 48.29 ms frame**. profile_hexgrid_cost.gd then removed
## HexGridMap's 18,769 nodes outright and recovered **1.60 ms**. An empty scene
## on the same machine, same window size, same vsync-off settings, runs at
## **0.22 ms**. So ~42 ms of the frame is real, is not in any node's per-frame
## script, and is not the canvas-item tree walk.
##
## Guessing at finer targets after that would be guessing. This halves the
## problem instead:
##
##   WORLD      hide WorldRoot — every renderer at once
##   HUD        hide MainHUD — every Control at once
##   PROCESS    set_process(false) on EVERY descendant of Main, recursively
##   AUTOLOADS  set_process(false) on the five real autoloads
##   ALL        all of the above together
##
## `ALL` is the floor: whatever is left after it is the engine plus this
## harness, and if `ALL` does not approach the 0.22 ms an empty scene costs
## then the remaining cost is in something none of these five reach — which is
## itself the finding, and a much better place to look next than another guess.
##
## Autoloads are included because they are the one per-frame surface the node
## ablation structurally could not reach: TickManager drives Engine.time_scale
## and the simulation clock, and a scaled delta makes every _process(delta) in
## the game do proportionally more work per frame.

const _WINDOW_SIZE := Vector2i(1280, 720)
const _ZOOM: float = 2.600
const _OFFSET := Vector2i(1, 0)
const _WARMUP_FRAMES: int = 300
const _SETTLE_FRAMES: int = 45
const _SAMPLE_FRAMES: int = 150

## The five real global autoloads, per CLAUDE.md §1.
const _AUTOLOADS: Array[String] = [
	"TickManager", "TimeCycleManager", "DisplaySettings",
	"GameLaunchState", "BackgroundExecutionManager",
]

var _main: Node
var _camera: CameraController


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: run this windowed — a headless viewport renders nothing.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_WINDOW_SIZE)
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

	_camera = _main.get_node("CameraController")
	_camera.edge_pan_enabled = false
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()

	var target := HexCoord.axial_to_world(start_hexes[0] + _OFFSET)
	_camera.global_position = target
	_camera.set_zoom_level(_ZOOM)
	for _f in _WARMUP_FRAMES:
		await get_tree().process_frame
	_camera.global_position = target
	_camera.set_zoom_level(_ZOOM)

	await _run()
	get_tree().quit(0)


func _run() -> void:
	print("Framed at zoom %.2f, %dx%d, vsync off. Empty-scene control on this machine: 0.22 ms.\n" % [
		_ZOOM, _WINDOW_SIZE.x, _WINDOW_SIZE.y])
	print("Engine.time_scale = %.3f  (TickManager sets this; a scaled delta makes every _process do more)" % Engine.time_scale)
	print("%-34s %8s %8s %9s %8s" % ["state", "med ms", "min ms", "recovered", "fps"])

	var base := await _sample()
	_row("as shipped", base, base["median"])

	var world: Node2D = _main.get_node("WorldRoot")
	# CanvasLayer, not CanvasItem — it carries `visible` but does not inherit
	# from CanvasItem, so a CanvasItem-typed local fails at runtime.
	var hud: CanvasLayer = _main.get_node("MainHUD")

	world.visible = false
	await _settle()
	_row("WorldRoot hidden", await _sample(), base["median"])
	world.visible = true

	hud.visible = false
	await _settle()
	_row("MainHUD hidden", await _sample(), base["median"])
	hud.visible = true

	var restored := _set_processing_recursively(_main, false)
	await _settle()
	_row("every _process off (whole tree)", await _sample(), base["median"])
	_restore_processing(restored)

	var autoload_state := _set_autoload_processing(false)
	await _settle()
	_row("autoloads' _process off", await _sample(), base["median"])
	_restore_autoloads(autoload_state)

	world.visible = false
	hud.visible = false
	restored = _set_processing_recursively(_main, false)
	autoload_state = _set_autoload_processing(false)
	await _settle()
	_row("ALL of the above", await _sample(), base["median"])
	_restore_processing(restored)
	_restore_autoloads(autoload_state)
	world.visible = true
	hud.visible = true

	print("\nIf 'ALL of the above' is still far from the 0.22 ms empty-scene control,")
	print("the cost is in something none of these five reach — say that, do not guess.")


## Returns the nodes actually changed, so restoring cannot accidentally ENABLE
## something that was off to begin with.
func _set_processing_recursively(node: Node, enabled: bool) -> Array[Node]:
	var changed: Array[Node] = []
	_walk(node, enabled, changed)
	return changed


func _walk(node: Node, enabled: bool, changed: Array[Node]) -> void:
	if node.is_processing() != enabled:
		node.set_process(enabled)
		changed.append(node)
	if node.is_physics_processing() != enabled:
		node.set_physics_process(enabled)
		if not changed.has(node):
			changed.append(node)
	for child in node.get_children():
		_walk(child, enabled, changed)


func _restore_processing(nodes: Array[Node]) -> void:
	for node in nodes:
		node.set_process(true)
		node.set_physics_process(true)


func _set_autoload_processing(enabled: bool) -> Array[Node]:
	var changed: Array[Node] = []
	for name in _AUTOLOADS:
		var node := get_node_or_null("/root/" + name)
		if node != null and node.is_processing() != enabled:
			node.set_process(enabled)
			changed.append(node)
	return changed


func _restore_autoloads(nodes: Array[Node]) -> void:
	for node in nodes:
		node.set_process(true)


func _settle() -> void:
	for _f in _SETTLE_FRAMES:
		await get_tree().process_frame


func _row(name: String, s: Dictionary, baseline_median: float) -> void:
	print("%-34s %8.2f %8.2f %9.2f %8.1f" % [
		name, s["median"], s["min"], baseline_median - s["median"],
		1000.0 / maxf(s["median"], 0.001)])


func _sample() -> Dictionary:
	var frames: Array[float] = []
	for _f in _SAMPLE_FRAMES:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
	frames.sort()
	return {"median": frames[frames.size() / 2], "min": frames[0]}
