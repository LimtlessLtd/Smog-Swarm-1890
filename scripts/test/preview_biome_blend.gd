extends Node2D

## Screenshots the terrain mesh at two zooms so the biome-boundary crossfade
## can be judged against the art it actually sits on.
##
## Run (NOT --headless -- this has to rasterise):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/preview_biome_blend.tscn
##
## The only question worth asking about TerrainBoundaryBlend is whether the
## boundary reads as soft WITHOUT the biome interior reading as washed out --
## "I just want the edges blurred over a gradient at the very edge of each
## biome change though, don't apply it to the entire biome" (user request).
## Neither half of that is answerable by an assertion. The pair of zooms
## matters: the blend band is one triangle wide (median 24 world units), so
## the far shot says whether it is visible at all at normal Tactical framing
## and the near shot says whether it is a gradient or a smear.
##
## Deliberately NOT Main.tscn -- that runs HexMapGenerator across the whole
## corridor, minutes per launch, and TerrainMeshView needs only a camera.

## Pennine edge east of Manchester: farmland, moorland and woodland all meet
## within one screen here, which is what makes it worth shooting. Flat
## single-biome country would prove nothing either way.
const _CAMERA_WORLD := Vector2(124153.4, 90624.0)

## Both comfortably inside the Tactical band (CameraController's threshold is
## 0.1875), which is the only zoom TerrainMeshView draws at.
const _FAR_ZOOM := 0.6
const _NEAR_ZOOM := 2.4

const _WARMUP_FRAMES: int = 180  ## Chunks stream in at CHUNKS_BUILT_PER_FRAME = 1.

var _camera: CameraController


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	_camera = load("res://scenes/camera/CameraController.tscn").instantiate()
	_camera.name = "CameraController"
	add_child(_camera)
	_camera.global_position = _CAMERA_WORLD
	_camera.zoom = Vector2.ONE * _FAR_ZOOM
	# Off, or this shoots a different place every run and no two renders are
	# comparable. CameraController edge-pans toward whichever window edge the
	# real OS mouse pointer is near, and it does not care that nobody is
	# playing -- across a 180-frame warmup that silently slid the camera by
	# thousands of world units, by an amount that depended on where the
	# pointer happened to be sitting and on how long each frame took. Cost
	# three renders that looked like a blend-width difference and were a
	# camera-position difference.
	_camera.edge_pan_enabled = false
	_camera.make_current()

	var mesh := Node2D.new()
	mesh.name = "TerrainMeshView"
	mesh.set_script(load("res://scripts/world/TerrainMeshView.gd"))
	mesh.set("camera_path", NodePath("../../CameraController"))
	world.add_child(mesh)

	var detail := Node2D.new()
	detail.name = "TerrainDetailView"
	detail.set_script(load("res://scripts/world/TerrainDetailView.gd"))
	detail.set("camera_path", NodePath("../../CameraController"))
	world.add_child(detail)

	_run()


func _run() -> void:
	await _shoot(_FAR_ZOOM, "user://biome_blend_far.png")
	await _shoot(_NEAR_ZOOM, "user://biome_blend_near.png")
	get_tree().quit(0)


func _shoot(zoom: float, path: String) -> void:
	_camera.zoom = Vector2.ONE * zoom
	for _i in _WARMUP_FRAMES:
		await get_tree().process_frame
	# The viewport texture is only valid after the frame has actually been
	# drawn; process_frame alone fires before the draw.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote %s (zoom %.2f)" % [ProjectSettings.globalize_path(path), zoom])
