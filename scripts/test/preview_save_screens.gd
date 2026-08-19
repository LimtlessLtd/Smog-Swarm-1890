extends Node2D

## Renders every screen of the campaign save/load flow against seeded save
## data, so the layouts can be judged rather than assumed.
##
## Run (NOT --headless -- this has to rasterise):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/preview_save_screens.tscn
##
## Four shots: the boot screen's New Campaign panel, its campaign list, one
## campaign drilled into its saves, and the in-game Save/Load panel. Every
## defect these screens can have -- a clipped field, a panel sized to the
## wrong one of two states, an unreadable thumbnail, a row that widens its
## list -- is invisible to an assertion and obvious in a picture. This
## project has shipped exactly that bug before (a LineEdit whose placeholder
## clipped to "Campaig", TechTreeView's list overflowing its panel).
##
## Seeds its own campaigns and deletes them afterwards, so it neither
## depends on nor disturbs whatever is really in user://saves.

const _CAMERA_WORLD := Vector2(124153.4, 90624.0)
const _ZOOM := 0.6
const _WARMUP_FRAMES: int = 240

## Deliberately varied: a long name (does a row clip it or widen the list?),
## a name with a filesystem-unsafe character (does the folder and the label
## agree?), and differing slot counts.
const _SEED := {
	"Manchester Campaign": ["Autumn 1890", "Before the siege", "Quicksave"],
	"The Long Winter of 1891": ["Day 153"],
	"Second try: no walls": ["Day 12", "Day 40"],
}

var _seeded_dirs: Array[String] = []


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

	_run()


func _run() -> void:
	for _i in _WARMUP_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	# Real game pixels for the seeded thumbnails, not a synthetic gradient:
	# whether a 320 px shot of THIS game reads at row size is one of the
	# questions these shots exist to answer.
	var frame := get_viewport().get_texture().get_image()
	var height := maxi(1, int(round(HUDScreenshotCapture.THUMBNAIL_WIDTH * float(frame.get_height()) / float(frame.get_width()))))
	frame.resize(HUDScreenshotCapture.THUMBNAIL_WIDTH, height, Image.INTERPOLATE_LANCZOS)
	frame.convert(Image.FORMAT_RGB8)

	var manager := SaveLoadManager.new()
	manager.name = "SeedManager"
	add_child(manager)
	_seed(manager, frame)

	# Inside a CanvasLayer, not straight onto this Node2D: a Control parented
	# to a Node2D is laid out in WORLD space and follows the camera, so at
	# this camera position the whole menu draws tens of thousands of units
	# off screen and the shot comes back as bare terrain. MainMenu.tscn is
	# its own scene root in the real game, where the viewport IS its parent.
	var menu_layer := CanvasLayer.new()
	menu_layer.name = "MenuLayer"
	add_child(menu_layer)
	var menu: Control = load("res://scenes/main/MainMenu.tscn").instantiate()
	menu.name = "MainMenu"
	menu_layer.add_child(menu)
	await get_tree().process_frame  ## MainMenuView builds its panels in _ready() and sizes them on the NEXT frame (_place_center()'s one-shot).

	var new_campaign: NewCampaignView = menu.get_node("NewCampaignView")
	var browser: CampaignBrowserView = menu.get_node("CampaignBrowserView")

	new_campaign.open()
	await _shot("user://preview_new_campaign.png")
	new_campaign.close()

	browser.open()
	await _shot("user://preview_campaign_list.png")

	# Drilled into a campaign's saves. Reached by delivering a real click to
	# the first campaign row rather than by calling the browser's own private
	# _show_slots(): the rows are HUDStyles.build_thumbnail_row() panels
	# driven by gui_input, so this goes through the same handler a mouse
	# press does, and a row that stopped responding to clicks would fail here
	# instead of being screenshotted around.
	var row := _first_campaign_row(browser)
	if row == null:
		print("FAIL: no campaign row found to click")
	else:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		row.gui_input.emit(click)
	await _shot("user://preview_campaign_saves.png")
	browser.close()

	menu_layer.queue_free()
	await get_tree().process_frame

	var hud := load("res://scenes/ui/MainHUD.tscn").instantiate() as CanvasLayer
	hud.name = "MainHUD"
	hud.set("save_load_manager_path", NodePath("../SeedManager"))
	add_child(hud)
	manager.set_active_campaign("Manchester Campaign")
	await get_tree().process_frame
	# The signal InGameMenuView emits when its "Save / Load..." row is
	# pressed. Firing it drives MainHUD's real handler, so this shot shows
	# the panel where and how the game actually puts it.
	var in_game_menu: InGameMenuView = hud.get_node("InGameMenuView")
	in_game_menu.save_load_requested.emit()
	await _shot("user://preview_save_load_panel.png")

	_cleanup()
	get_tree().quit(0)


## The campaign list's first row. Walks the scene tree (public API) rather
## than reading CampaignBrowserView's own node references, and skips the
## SaveSlotList half so it can't return a SLOT row while the browser is
## still showing campaigns.
func _first_campaign_row(browser: CampaignBrowserView) -> Control:
	for node in _descendants(browser):
		if node is ScrollContainer and not (node is SaveSlotList):
			for column in node.get_children():
				for row in column.get_children():
					if row is PanelContainer:
						return row
	return null


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _seed(manager: SaveLoadManager, thumbnail: Image) -> void:
	for campaign_name: String in _SEED:
		manager.set_active_campaign(campaign_name)
		_seeded_dirs.append(manager.get_active_campaign())
		for slot_name: String in _SEED[campaign_name]:
			manager.save_game(slot_name, thumbnail)


func _cleanup() -> void:
	for dir_name in _seeded_dirs:
		var dir_path := "%s/%s" % [SaveLoadManager.SAVES_ROOT, dir_name]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				dir.remove(entry)
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(dir_path)
