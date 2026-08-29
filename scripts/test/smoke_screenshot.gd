extends Node

## Boots a FRESH game and asserts the screen is not visually broken at five
## framings either side of the Tactical threshold.
##
## Run (NOT --headless -- a headless viewport has no texture to read, the same
## constraint capture_project_review_shots.gd, verify_save_screenshot.gd and
## preview_relief_ingame.gd all record):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/smoke_screenshot.tscn
##
## Exit 0 if every frame renders something; 1 if any frame is degenerate. PNGs are
## written either way, because "it failed" is not useful without the image.
##
## WHY THIS EXISTS: every real visual defect in this project was found by looking at
## an image, never by reasoning about the code -- the fog-vs-tree z-index tie (PR #89)
## and the Tech Tree panel drawing as an empty black rectangle are both defects no
## headless verification could have caught. run_verifications.py gates logic; this
## gates whether anything is on screen at all.
##
## Deliberately NOT the user's save, unlike capture_project_review_shots.gd: a gate
## must run on a fresh checkout, so this frames the generated starting settlement via
## BuildingManager.get_starting_settlement_hexes() rather than hardcoded save
## coordinates.
##
## The camera-handling here duplicates capture_project_review_shots.gd's framing
## discipline (input immunity, set_zoom_level() rather than assigning `zoom`, waiting
## real frames rather than assuming). That is now the fourth script carrying this
## logic; if a fifth appears, extract it rather than copying it again.

const _WINDOW_SIZE := Vector2i(1280, 720)
const _OUT_DIR := "user://smoke_shots"

## Relief streams 2 tiles/frame toward MAX_TILES_IN_VIEW=96 and a dense mesh chunk
## build is ~90-170 ms on its own frame, so a shot taken immediately after a camera
## move photographs half-streamed terrain and would fail for the wrong reason.
const _WARMUP_FRAMES: int = 200
const _FIRST_WARMUP_FRAMES: int = 320

## Zooms straddle CameraController.tactical_zoom_threshold (0.1875) deliberately:
## Strategic and Tactical are different renderers, not two magnifications of one.
##
## Shot 5 is past high_fidelity_threshold (2.0), which is the ONLY band where
## design_doc.md §2.1's individual zombies draw at all — the other four are
## Strategic markers, LOW blobs or MEDIUM clusters. It is offset onto a
## neighbouring hex because the player's own starting hex is Cleared by D7's
## ring seed: framing the settlement itself would photograph empty ground and
## call it a pass.
const _SHOTS: Array[Dictionary] = [
	{"name": "01_strategic_country", "zoom": 0.010, "note": "Whole island, sea and fog"},
	{"name": "02_strategic_colony", "zoom": 0.110, "note": "Colony below the Tactical threshold"},
	{"name": "03_tactical_entry", "zoom": 0.230, "note": "Past the threshold: terrain mesh takes over"},
	{"name": "04_tactical_close", "zoom": 1.300, "note": "Buildings, walls and units"},
	{"name": "05_tactical_crowd", "zoom": 2.600, "offset": Vector2i(1, 0), "note": "HIGH fidelity: individual zombies on an infested neighbour"},
]

## A degenerate frame is one nothing rendered into. Thresholds are deliberately
## slack -- this catches "black screen" and "one flat colour", not subtle regressions,
## because a tight threshold on a streamed renderer would flake.
const _SAMPLE_COLS: int = 64
const _SAMPLE_ROWS: int = 36
const _MIN_DISTINCT_COLORS: int = 12
const _MAX_SINGLE_COLOR_FRACTION: float = 0.98

var _main: Node
var _camera: CameraController
var _failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: run this windowed, not --headless -- a headless viewport has no texture to read.")
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
	# "BuildingManager", not "WorldRoot/BuildingManager": that path has been
	# wrong since this file was written (commit dcdf2ddf), so get_node()
	# returned null and the very first thing this gate did was crash. Found
	# 2026-08-29 the first time it was run since.
	var building_manager: BuildingManager = _main.get_node("BuildingManager")
	var start_hexes: Array[Vector2i] = building_manager.get_starting_settlement_hexes()
	if start_hexes.is_empty():
		print("FAIL: no starting settlement to frame -- map generated with nothing on it.")
		get_tree().quit(1)
		return
	var focus: Vector2i = start_hexes[0]

	_camera = _main.get_node("CameraController")
	# edge_pan_enabled alone is not enough: _process() edge/key-pans, _input()
	# middle-drags and _unhandled_input() zooms on the wheel, all from whatever the
	# real desktop sends this window while it sits open for minutes.
	_camera.edge_pan_enabled = false
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()

	_capture_all(focus)


func _capture_all(focus: Vector2i) -> void:
	print("Framing starting settlement at %s\n" % focus)
	for i in range(_SHOTS.size()):
		var shot: Dictionary = _SHOTS[i]
		var target_zoom: float = shot["zoom"]
		var framed: Vector2i = focus + (shot.get("offset", Vector2i.ZERO) as Vector2i)

		_camera.global_position = HexCoord.axial_to_world(framed)
		_camera.set_zoom_level(target_zoom)  ## Not `zoom =` -- that skips the tactical_mode_changed/tactical_fidelity_changed signals LocalDetailManager and TacticalEntityLayer hydrate off.

		var warmup: int = _FIRST_WARMUP_FRAMES if i == 0 else _WARMUP_FRAMES
		for _f in warmup:
			await get_tree().process_frame

		# Re-assert rather than trust it survived the warmup.
		var target_position := HexCoord.axial_to_world(framed)
		_camera.global_position = target_position
		_camera.set_zoom_level(target_zoom)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		# A shot framed somewhere other than where it was aimed would pass or fail for
		# the wrong reason. capture_project_review_shots.gd records the case: a stray
		# desktop mouse wheel over the window rezoomed the camera mid-run.
		var zoom_drifted: bool = absf(_camera.zoom.x - target_zoom) > 0.0001
		var position_drifted: bool = _camera.global_position.distance_to(target_position) > 1.0
		if zoom_drifted or position_drifted:
			_failures.append("%s framed wrong: wanted %s @ %.3f, got %s @ %.3f"
				% [shot["name"], target_position, target_zoom,
					_camera.global_position, _camera.zoom.x])

		var image := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [_OUT_DIR, shot["name"]]
		image.save_png(path)
		_check(shot, image, path)
		_report_crowd()

	print()
	if _failures.is_empty():
		print("All %d frames rendered. PNGs in %s"
			% [_SHOTS.size(), ProjectSettings.globalize_path(_OUT_DIR)])
	else:
		print("DEGENERATE FRAMES (%d):" % _failures.size())
		for f in _failures:
			print("  " + f)
		print("Look at the PNGs in %s before assuming this is a false positive."
			% ProjectSettings.globalize_path(_OUT_DIR))
	get_tree().quit(1 if not _failures.is_empty() else 0)


## How many individuals the tactical layer actually instantiated for the frame
## just captured. Printed, never asserted: the count depends on
## ZombieSwarmManager.ENTITY_BUDGET and on the baked population under the
## camera, both tuning inputs rather than rules, and the degenerate-frame check
## below is what decides pass or fail. It is here so the person looking at
## 05_tactical_crowd.png knows whether an empty-looking frame means "the
## renderer is broken" or "there was nothing on that hex".
func _report_crowd() -> void:
	var swarms: ZombieSwarmManager = _main.get_node_or_null("ZombieSwarmManager")
	if swarms == null:
		return
	print("        tactical layer: %d individuals in %d crowds"
		% [swarms.get_entity_count(), swarms.get_group_count()])



## Quantised to 5 bits per channel so gradient dithering and the streamed relief's
## own noise don't read as "lots of distinct colours" on an otherwise blank frame.
func _check(shot: Dictionary, image: Image, path: String) -> void:
	var counts: Dictionary = {}
	var total: int = 0
	for cy in _SAMPLE_ROWS:
		for cx in _SAMPLE_COLS:
			var px: int = int(float(cx) / _SAMPLE_COLS * image.get_width())
			var py: int = int(float(cy) / _SAMPLE_ROWS * image.get_height())
			var c := image.get_pixel(px, py)
			var key: int = (int(c.r * 31) << 10) | (int(c.g * 31) << 5) | int(c.b * 31)
			counts[key] = counts.get(key, 0) + 1
			total += 1

	var distinct: int = counts.size()
	var dominant: int = 0
	for k in counts:
		dominant = maxi(dominant, counts[k])
	var fraction: float = float(dominant) / float(total)

	var ok: bool = distinct >= _MIN_DISTINCT_COLORS and fraction <= _MAX_SINGLE_COLOR_FRACTION
	print("  %s  %-24s %3d colors, %4.1f%% single  %s"
		% ["ok  " if ok else "FAIL", shot["name"], distinct, fraction * 100.0, shot["note"]])
	if not ok:
		_failures.append("%s (%d distinct colors, %.1f%% one color) -> %s"
			% [shot["name"], distinct, fraction * 100.0, path])
