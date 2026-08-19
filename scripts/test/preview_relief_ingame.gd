extends Node2D

## Renders the relief tiles over the real terrain mesh and saves a screenshot,
## so the shading can be judged against the art it actually sits on.
##
## Run (NOT --headless -- this has to rasterise):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/preview_relief_ingame.tscn
##
## tools/geo_bake/relief_tiles_preview.png shows the baked tiles on their own,
## which proves the bake but says nothing about the only question that matters
## for the shader: whether the strength reads as terrain relief once composited
## over TerrainMeshView's biome textures, or whether it is invisible at one end
## and a grey film at the other. Those constants
## (assets/shaders/relief_hillshade.gdshader's shadow_gain/light_gain) can only
## be judged by looking.
##
## Deliberately NOT Main.tscn. That runs HexMapGenerator across the whole
## corridor -- minutes per launch (scripts/test/verify_gates.gd's own note) --
## and none of it is needed here: TerrainMeshView loads baked chunks and asks
## only for a camera, ReliefTileView asks only for a camera, and neither reads
## HexGridMap at all. So this scene is those two layers plus a camera, which
## makes iterating on shader constants a few seconds rather than a few minutes.
##
## Frames are waited on rather than assumed: both layers stream their content in
## across several _process() calls (CHUNKS_BUILT_PER_FRAME / TILES_LOADED_PER_FRAME),
## so capturing on frame one would reliably photograph an empty screen.

## Over the Pennine edge east of Manchester -- the corridor's most legible
## relief. Flat ground is the wrong place to judge a hillshade.
const _CAMERA_WORLD := Vector2(124153.4, 90624.0)

## Comfortably inside the Tactical band (CameraController.tactical_zoom_threshold
## is 0.1875), which is the only zoom where ReliefTileView draws at all.
const _ZOOM := 0.6

const _WARMUP_FRAMES: int = 240  ## Generous: ~40 tiles at TILES_LOADED_PER_FRAME=2 plus chunk builds at 1/frame.
const _OUT_PATH := "user://relief_ingame.png"

var _camera: CameraController


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	_camera = load("res://scenes/camera/CameraController.tscn").instantiate() if ResourceLoader.exists("res://scenes/camera/CameraController.tscn") else null
	if _camera == null:
		print("FAIL: CameraController.tscn not found")
		get_tree().quit(1)
		return
	_camera.name = "CameraController"
	add_child(_camera)
	_camera.global_position = _CAMERA_WORLD
	_camera.zoom = Vector2.ONE * _ZOOM
	_camera.make_current()

	var mesh := Node2D.new()
	mesh.name = "TerrainMeshView"
	mesh.set_script(load("res://scripts/world/TerrainMeshView.gd"))
	mesh.set("camera_path", NodePath("../../CameraController"))
	world.add_child(mesh)

	var relief := Node2D.new()
	relief.name = "ReliefTileView"
	relief.set_script(load("res://scripts/world/ReliefTileView.gd"))
	relief.set("camera_path", NodePath("../../CameraController"))
	world.add_child(relief)

	_capture()


func _capture() -> void:
	for _i in _WARMUP_FRAMES:
		await get_tree().process_frame
	# The viewport texture is only valid after the frame has actually been
	# drawn; process_frame alone fires before the draw.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_OUT_PATH)
	if error != OK:
		print("FAIL: could not write %s (error %d)" % [_OUT_PATH, error])
		get_tree().quit(1)
		return
	print("camera at %s zoom %.3f (tactical=%s)" % [_CAMERA_WORLD, _ZOOM, _camera.is_tactical_zoom()])
	print("wrote %s" % ProjectSettings.globalize_path(_OUT_PATH))
	get_tree().quit(0)
