extends Node

## Screenshots the boot menu, so the data-attribution footer can be checked
## by LOOKING at it rather than by trusting that a Label with the right text
## in it also lands somewhere readable and unclipped.
##
## Run (NOT --headless -- a headless viewport has no texture to read):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/capture_main_menu_shot.tscn
##
## Separate from capture_project_review_shots.gd because MainMenu.tscn is a
## different scene entirely (project.godot's own run/main_scene) and needs
## none of the multi-minute HexMapGenerator boot that one pays for.

const _OUT_PATH := "user://review_shots/00_main_menu.png"
const _WINDOW_SIZE := Vector2i(1600, 900)
const _WARMUP_FRAMES: int = 30  ## Only has to outlast _place_center()'s one-frame content resize.


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_WINDOW_SIZE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://review_shots"))

	add_child(load("res://scenes/main/MainMenu.tscn").instantiate())
	_capture()


func _capture() -> void:
	for _f in _WARMUP_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_width() <= 0:
		print("FAIL: no viewport image (running --headless?)")
		get_tree().quit(1)
		return
	image.convert(Image.FORMAT_RGB8)
	var error := image.save_png(_OUT_PATH)
	if error != OK:
		print("FAIL: could not write %s (error %d)" % [_OUT_PATH, error])
		get_tree().quit(1)
		return
	print("wrote %s" % ProjectSettings.globalize_path(_OUT_PATH))
	get_tree().quit(0)
