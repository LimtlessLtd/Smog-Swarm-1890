extends Node

## Two Tactical frames of the same starting settlement — everything running,
## then everything the player is allowed to switch off switched off — so the
## "going dark" tint and the dropped smoke/fire/lamp can be LOOKED AT rather
## than reasoned about (`CLAUDE.md` §0.1: every real visual defect in this
## project was found by looking at an image).
##
## A preview, not a gate: `run_verifications.py` only discovers `verify_*.gd`,
## and what this produces is a pair of images for a human, not a pass/fail.
## `verify_building_power.gd` is the gate for the simulation half.
##
## Run (NOT --headless — a headless viewport has no texture to read, the same
## constraint smoke_screenshot.gd records):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/preview_going_dark.tscn
##
## Framing discipline (input immunity, set_zoom_level() rather than assigning
## `zoom`, waiting real frames rather than assuming) is smoke_screenshot.gd's,
## which is the fifth copy of it — extracting it is filed in `backlog.md`
## rather than done here, since this file is the one that makes the case.

const _WINDOW_SIZE := Vector2i(1280, 720)
const _OUT_DIR := "user://going_dark_shots"
const _ZOOM: float = 1.300  ## smoke_screenshot.gd's "Buildings, walls and units" framing.
const _WARMUP_FRAMES: int = 320
const _SETTLE_FRAMES: int = 200

var _main: Node
var _camera: CameraController
var _buildings: BuildingManager


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: run this windowed, not --headless — a headless viewport has no texture to read.")
		get_tree().quit(1)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_WINDOW_SIZE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_OUT_DIR))

	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_on_map_ready()
	else:
		hex_grid_map.generation_completed.connect(_on_map_ready)


func _on_map_ready() -> void:
	_buildings = _main.get_node("BuildingManager")
	var start_hexes: Array[Vector2i] = _buildings.get_starting_settlement_hexes()
	if start_hexes.is_empty():
		print("FAIL: no starting settlement to frame — map generated with nothing on it.")
		get_tree().quit(1)
		return

	_camera = _main.get_node("CameraController")
	# Same input immunity smoke_screenshot.gd applies, and for the same reason:
	# this window sits open for minutes and takes whatever the desktop sends it.
	_camera.edge_pan_enabled = false
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()

	_capture(start_hexes[0])


func _capture(focus: Vector2i) -> void:
	var target := HexCoord.axial_to_world(focus)
	_camera.global_position = target
	_camera.set_zoom_level(_ZOOM)
	await _wait(_WARMUP_FRAMES)
	_camera.global_position = target
	_camera.set_zoom_level(_ZOOM)
	await _shoot("01_running")

	var switched := 0
	for instance in _buildings.get_all_buildings():
		if _buildings.power_down_building(instance):
			switched += 1
	print("switched off %d of %d starting buildings (the rest are always_powered or not yet built)"
		% [switched, _buildings.get_all_buildings().size()])

	# building_powered_down reaches TacticalHexView through
	# LocalDetailManager's dehydrate/rehydrate, which takes frames.
	await _wait(_SETTLE_FRAMES)
	await _shoot("02_dark")

	print("\nTwo frames in %s — compare them." % ProjectSettings.globalize_path(_OUT_DIR))
	get_tree().quit(0)


func _shoot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_OUT_DIR, name])
	print("  wrote %s.png" % name)


func _wait(frames: int) -> void:
	for _f in frames:
		await get_tree().process_frame
