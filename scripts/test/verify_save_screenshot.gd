extends Node2D

## Exercises the save-slot screenshot end to end against the REAL MainHUD,
## and writes out what it captured so the result can be looked at.
##
## Run (NOT --headless -- this has to rasterise, and a headless viewport has
## no texture to read):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/verify_save_screenshot.tscn
##
## Two independent things need checking and only one of them is provable by
## assertion:
##   - The FILE LAYOUT (a campaign folder holding <slot>.res and its
##     <slot>.png, both findable through the listing API the browsers use)
##     is checked here and this exits non-zero if it breaks.
##   - Whether the shot is actually free of HUD, and whether the game is
##     recognisable at 320 px, can only be judged by opening the images. It
##     writes three: the frame with the HUD up, the thumbnail, and the frame
##     after the capture (which must have the HUD back).
##
## Deliberately NOT Main.tscn: that runs HexMapGenerator across the whole
## corridor, minutes per launch (verify_gates.gd's own note), and none of it
## is needed to answer either question. TerrainMeshView draws baked chunks
## from a camera alone, and MainHUD tolerates every one of its manager
## NodePaths being unset -- so this is the real HUD, over real terrain,
## in seconds. What it does NOT cover is MainHUD's own three-line wiring of
## the two together; Main.tscn booting clean covers that.

const _CAMERA_WORLD := Vector2(124153.4, 90624.0)  ## Pennine edge east of Manchester — a flat plain would prove nothing about a thumbnail's legibility.
const _ZOOM := 0.6
const _WARMUP_FRAMES: int = 240  ## Terrain chunks and relief tiles stream in over many frames; capturing early photographs an empty screen.

const _CAMPAIGN := "Verify Campaign"
const _SLOT := "Autumn 1890"

const _BEFORE_PATH := "user://verify_save_hud_up.png"
const _AFTER_PATH := "user://verify_save_hud_restored.png"
const _THUMB_COPY_PATH := "user://verify_save_thumbnail.png"

var _failures: Array[String] = []


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	var camera: CameraController = load("res://scenes/camera/CameraController.tscn").instantiate()
	camera.name = "CameraController"
	add_child(camera)
	camera.global_position = _CAMERA_WORLD
	camera.zoom = Vector2.ONE * _ZOOM
	camera.make_current()

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

	var manager := SaveLoadManager.new()
	manager.name = "SaveLoadManager"
	add_child(manager)

	var hud := load("res://scenes/ui/MainHUD.tscn").instantiate() as CanvasLayer
	hud.name = "MainHUD"
	add_child(hud)

	_run(manager, hud)


func _run(manager: SaveLoadManager, hud: CanvasLayer) -> void:
	for _i in _WARMUP_FRAMES:
		await get_tree().process_frame

	# The viewport texture is only valid after the frame has actually been
	# drawn; process_frame alone fires before the draw.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_BEFORE_PATH)

	manager.set_active_campaign(_CAMPAIGN)
	_check(manager.get_active_campaign() == _CAMPAIGN,
		"active campaign is '%s', expected '%s'" % [manager.get_active_campaign(), _CAMPAIGN])

	var capture := HUDScreenshotCapture.new(hud, get_viewport())
	var thumbnail: Image = await capture.capture()

	_check(thumbnail != null, "capture() returned null")
	if thumbnail != null:
		_check(thumbnail.get_width() == HUDScreenshotCapture.THUMBNAIL_WIDTH,
			"thumbnail is %d px wide, expected %d" % [thumbnail.get_width(), HUDScreenshotCapture.THUMBNAIL_WIDTH])
		thumbnail.save_png(_THUMB_COPY_PATH)
	_check(hud.visible, "HUD was left hidden after the capture")

	_check(manager.save_game(_SLOT, thumbnail), "save_game() reported failure")

	# What the browsers actually call, rather than the private path layout:
	# a save that exists on disk but that get_slot_names()/get_slot_thumbnail()
	# can't see is exactly the bug this is here to catch.
	_check(manager.get_campaign_names().has(_CAMPAIGN),
		"get_campaign_names() is missing '%s' (got %s)" % [_CAMPAIGN, manager.get_campaign_names()])
	_check(manager.get_slot_names(_CAMPAIGN).has(_SLOT),
		"get_slot_names() is missing '%s' (got %s)" % [_SLOT, manager.get_slot_names(_CAMPAIGN)])
	_check(manager.get_slot_thumbnail(_CAMPAIGN, _SLOT) != null, "get_slot_thumbnail() returned null")
	_check(manager.get_campaign_thumbnail(_CAMPAIGN) != null, "get_campaign_thumbnail() returned null")
	_check(manager.get_latest_slot_name(_CAMPAIGN) == _SLOT,
		"get_latest_slot_name() returned '%s'" % manager.get_latest_slot_name(_CAMPAIGN))
	var modified := manager.get_slot_modified_time(_CAMPAIGN, _SLOT)
	_check(modified > 0, "get_slot_modified_time() returned %d" % modified)
	_check(not SaveTimeFormat.describe(modified).is_empty(), "SaveTimeFormat.describe() came out empty")

	# The thumbnail must NOT register as a slot of its own — get_slot_names()
	# collects by extension, and a .png sharing its slot's basename sitting in
	# the same folder is the obvious way for that to go wrong.
	_check(manager.get_slot_names(_CAMPAIGN).size() == 1,
		"campaign holds %d slots, expected 1" % manager.get_slot_names(_CAMPAIGN).size())

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_AFTER_PATH)

	_delete_campaign(manager)

	for path in [_BEFORE_PATH, _THUMB_COPY_PATH, _AFTER_PATH]:
		print("wrote %s" % ProjectSettings.globalize_path(path))
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("%d checks failed" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


## Leaves no "Verify Campaign" behind in the player's own save list. Uses the
## same public listing API rather than assuming the file layout.
func _delete_campaign(manager: SaveLoadManager) -> void:
	var dir_path := "%s/%s" % [SaveLoadManager.SAVES_ROOT, _CAMPAIGN]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
