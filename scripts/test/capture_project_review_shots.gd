extends Node

## Captures a set of review screenshots of the REAL game — the user's own
## "Manchester Campaign" save loaded through the real Main.tscn, framed at a
## spread of zoom levels from whole-country Strategic down to individual
## buildings in Tactical, with the HUD left visible.
##
## Run (NOT --headless -- a headless viewport has no texture to read, the same
## constraint verify_save_screenshot.gd and preview_relief_ingame.gd record):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/capture_project_review_shots.tscn
##
## Deliberately the REAL Main.tscn, unlike preview_relief_ingame.gd's
## deliberately-light two-layer scene. That scene exists to iterate on shader
## constants in seconds; this one exists to photograph what a player actually
## sees, which means the whole stack — fog, HUD, entities, overlays, the save's
## real buildings and walls — has to be present. The multi-minute
## HexMapGenerator boot (verify_gates.gd's own note) is the price.
##
## The camera is made fully INPUT-IMMUNE, which is broader than the
## edge_pan_enabled fix todo.md already records. That entry ("Soft biome
## boundaries", 2026-08-19) caught edge-panning — CameraController edge-pans
## toward whichever window edge the real OS mouse pointer is near and does not
## care that nobody is playing. But this window is open on a real desktop for
## minutes, and a stray mouse WHEEL over it also reaches _unhandled_input()
## and rezooms the camera: measured on this script's own first run, shot 7
## reported tactical=false at an intended zoom of 0.550 (which is well above
## tactical_zoom_threshold) and the Tactical shots came back framed inside a
## single texture cell. So _process/_input/_unhandled_input are all disabled
## outright, and position/zoom are re-asserted immediately before each capture
## rather than trusted to have survived the warmup.
##
## Zoom goes through CameraController.set_zoom_level(), NOT a direct `zoom`
## assignment. Assigning `zoom` skips tactical_mode_changed/
## tactical_fidelity_changed, which is what LocalDetailManager hydrates props
## and buildings off and what TacticalEntityLayer swaps figure fidelity off —
## a harness that sets `zoom` by hand photographs Tactical terrain with
## neither applied, and nothing reports an error.
##
## Frames are waited on rather than assumed, per preview_relief_ingame.gd:
## TerrainMeshView and TerrainDetailView build one chunk per frame and
## ReliefTileView loads TILES_LOADED_PER_FRAME, so a shot taken immediately
## after moving the camera photographs half-streamed terrain.

const _CAMPAIGN := "Manchester Campaign"
const _SLOT := "yu5tytgt"
const _OUT_DIR := "user://review_shots"

## Windowed at a fixed size rather than the project's own fullscreen
## (window/size/mode=3), so shot dimensions don't depend on whichever monitor
## this runs on.
const _WINDOW_SIZE := Vector2i(1600, 900)

## Frames to wait after each camera move before capturing. Generous: relief
## streams 2 tiles/frame toward MAX_TILES_IN_VIEW=96, and a dense mesh chunk
## build is ~90-170 ms on its own frame.
const _WARMUP_FRAMES: int = 200
const _FIRST_WARMUP_FRAMES: int = 320  ## The first shot also pays for post-load hydration.

## Framed on the save's own content: (80,118) is the Manchester starting
## settlement, (81,147) the second settlement founded by Town Hall, (86,113)
## the nearest live horde measured at 6 hexes out. Zooms straddle
## CameraController.tactical_zoom_threshold (0.1875) deliberately — Strategic
## and Tactical are different renderers, not just different magnifications.
const _SHOTS: Array[Dictionary] = [
	{"name": "01_strategic_country", "coord": Vector2i(80, 130), "zoom": 0.010,
		"note": "Whole-island Strategic: real coastline, drawn sea, fog of war"},
	{"name": "02_strategic_region", "coord": Vector2i(80, 124), "zoom": 0.045,
		"note": "Regional Strategic: explored cluster against unexplored ground"},
	{"name": "03_strategic_colony", "coord": Vector2i(80, 118), "zoom": 0.110,
		"note": "Colony at Strategic, just below the Tactical threshold"},
	{"name": "04_tactical_entry", "coord": Vector2i(80, 118), "zoom": 0.230,
		"note": "Just past tactical_zoom_threshold: vector terrain mesh takes over"},
	{"name": "05_tactical_mid", "coord": Vector2i(80, 118), "zoom": 0.550,
		"note": "Tactical mid: biome polygons, boundary blend, relief hillshade, prop scatter"},
	{"name": "06_tactical_close", "coord": Vector2i(80, 118), "zoom": 1.300,
		"note": "Tactical close: individual buildings, walls, gates and units"},
	{"name": "07_second_settlement", "coord": Vector2i(81, 147), "zoom": 0.550,
		"note": "The second settlement founded via Town Hall"},
	{"name": "08_horde_ground", "coord": Vector2i(86, 113), "zoom": 0.400,
		"note": "Nearest live horde's ground, 6 hexes from the colony"},
]

var _main: Node
var _camera: CameraController
var _written: Array[String] = []


func _ready() -> void:
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
	var save_load: SaveLoadManager = _main.get_node("SaveLoadManager")
	save_load.set_active_campaign(_CAMPAIGN)
	if not save_load.load_game(_SLOT):
		print("FAIL: could not load save '%s' in campaign '%s'" % [_SLOT, _CAMPAIGN])
		get_tree().quit(1)
		return

	_camera = _main.get_node("CameraController")
	# See this class's own doc comment. edge_pan_enabled alone is not enough:
	# _process() edge/key-pans, _input() middle-drags, and _unhandled_input()
	# zooms on the wheel, all from whatever the real desktop sends this window.
	_camera.edge_pan_enabled = false
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()

	_capture_all()


func _capture_all() -> void:
	for i in range(_SHOTS.size()):
		var shot: Dictionary = _SHOTS[i]
		var target_position := HexCoord.axial_to_world(shot["coord"])
		var target_zoom := float(shot["zoom"])
		_camera.global_position = target_position
		_camera.set_zoom_level(target_zoom)  ## Not `zoom =` — see this class's doc comment.

		var warmup: int = _FIRST_WARMUP_FRAMES if i == 0 else _WARMUP_FRAMES
		for _f in warmup:
			await get_tree().process_frame

		# Re-assert after the warmup, not just before it. Input processing is
		# disabled above, but re-stating the framing costs one assignment and
		# removes any remaining way for a long warmup to photograph somewhere
		# other than where this shot claims to be.
		_camera.global_position = target_position
		_camera.set_zoom_level(target_zoom)
		await get_tree().process_frame
		# The viewport texture is only valid after the frame has actually been
		# DRAWN; process_frame alone fires before the draw.
		await RenderingServer.frame_post_draw

		# Assert rather than trust: the whole point of the two guards above is
		# that this can silently drift, and a mislabeled screenshot is worse
		# than a missing one.
		if absf(_camera.zoom.x - target_zoom) > 0.0001 or _camera.global_position.distance_to(target_position) > 1.0:
			print("FAIL: %s drifted — wanted pos=%s zoom=%.4f, got pos=%s zoom=%.4f" % [
				shot["name"], target_position, target_zoom, _camera.global_position, _camera.zoom.x])
			get_tree().quit(1)
			return

		var image := get_viewport().get_texture().get_image()
		if image == null or image.get_width() <= 0:
			print("FAIL: no viewport image for %s (running --headless?)" % [shot["name"]])
			get_tree().quit(1)
			return
		image.convert(Image.FORMAT_RGB8)  ## Alpha is a constant 1 over a fully-painted frame and only costs file size.

		var path: String = "%s/%s.png" % [_OUT_DIR, shot["name"]]
		var error := image.save_png(path)
		if error != OK:
			print("FAIL: could not write %s (error %d)" % [path, error])
			get_tree().quit(1)
			return
		_written.append(ProjectSettings.globalize_path(path))
		print("[%d/%d] %s  hex=%s zoom=%.3f tactical=%s  %s" % [
			i + 1, _SHOTS.size(), shot["name"], shot["coord"], float(shot["zoom"]),
			_camera.is_tactical_zoom(), shot["note"]])

	print("\nwrote %d shots to %s" % [_written.size(), ProjectSettings.globalize_path(_OUT_DIR)])
	get_tree().quit(0)
