class_name MainMenuView
extends Control

## Boot-screen title menu — "There should be a 'Main Menu' that has all the
## save/load functionality on it, it should also have all the display
## options... it should also have options for 'New Game' and 'Exit'" (user
## feedback). `project.godot`'s `run/main_scene` (MainMenu.tscn, a single
## Control node with this script; every child built in code, same "no
## editor session to lay out a Control tree by hand" convention MainHUD's
## own header comment documents).
##
## Owns a private, UNWIRED SaveLoadManager purely for
## get_campaign_names()/get_slot_names() (plain `user://saves` directory
## listing, no manager NodePaths needed for either) — this scene has no
## live BuildingManager/ResourceManager/etc. to load state INTO yet.
## "Continue" therefore can't call SaveLoadManager.load_game() directly;
## it records the chosen campaign/slot on the GameLaunchState autoload and
## changes scene to Main.tscn, whose own `_ready()` consumes it and
## performs the real load once every manager SaveLoadManager needs
## actually exists (see GameLaunchState's own doc comment for the full
## handoff). Same reasoning is why the embedded SaveLoadView here has its
## Save button hidden (SaveLoadView.set_save_enabled(false)) — there's
## nothing live to save FROM this screen.
##
## Display Options works identically to its in-game counterpart with zero
## special-casing: DisplaySettings is a plain autoload, independent of
## whether a game is currently running.

const MENU_WIDTH := 260.0
const OVERLAY_SIZE := Vector2(340.0, 320.0)

var _save_load_manager: SaveLoadManager
var _save_load_view: SaveLoadView
var _display_options_view: DisplayOptionsView

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = HUDStyles.PANEL_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var title := Label.new()
	title.text = "SMOG & SWARM, 1890"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HUDStyles.style_label(title, true)
	title.add_theme_font_size_override("font_size", 36)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 48)
	title.offset_left = -300.0
	title.offset_right = 300.0
	title.offset_top = 64.0
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A steam-and-cordite defense of Manchester"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HUDStyles.style_label(subtitle, false, true)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 48)
	subtitle.offset_left = -300.0
	subtitle.offset_right = 300.0
	subtitle.offset_top = 108.0
	add_child(subtitle)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	menu.offset_left = -MENU_WIDTH / 2.0
	menu.offset_right = MENU_WIDTH / 2.0
	add_child(menu)

	menu.add_child(_menu_button("New Game", _on_new_game_pressed))
	menu.add_child(_menu_button("Continue...", _on_continue_pressed))
	menu.add_child(_menu_button("Display Options...", _on_display_options_pressed))
	menu.add_child(_menu_button("Exit", _on_exit_pressed))

	_save_load_manager = SaveLoadManager.new()
	_save_load_manager.name = "SaveLoadManager"
	add_child(_save_load_manager)

	_save_load_view = SaveLoadView.new()
	_save_load_view.name = "SaveLoadView"
	add_child(_save_load_view)
	_place_center(_save_load_view, OVERLAY_SIZE)
	_save_load_view.setup(_save_load_manager)
	_save_load_view.set_save_enabled(false)
	_save_load_view.load_requested.connect(_on_load_requested)

	_display_options_view = DisplayOptionsView.new()
	_display_options_view.name = "DisplayOptionsView"
	add_child(_display_options_view)
	_place_center(_display_options_view, OVERLAY_SIZE)

func _menu_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	HUDStyles.style_button(button)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(on_pressed)
	return button

## Same "size to real content, don't trust a hand-picked rect" pattern
## MainHUD._place_center() already uses for these exact two view classes —
## duplicated rather than shared because this scene has no MainHUD
## instance to call into (it boots BEFORE Main.tscn even exists).
func _place_center(control: Control, fallback_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -fallback_size.x / 2.0
	control.offset_right = fallback_size.x / 2.0
	control.offset_top = -fallback_size.y / 2.0
	control.offset_bottom = fallback_size.y / 2.0
	if control.has_method("get_content_min_size"):
		# A fresh lambda per call, not a shared bound method — see
		# MainHUD._place_top_right()'s own note on why (multiple panels
		# resolving through one shared method+signal hit an "only the
		# first one actually fires" problem).
		get_tree().process_frame.connect(func() -> void:
			if not is_instance_valid(control):
				return
			var content: Vector2 = control.get_content_min_size()
			if content.x <= 0.0 or content.y <= 0.0:
				return
			var size := content + Vector2(20.0, 16.0)
			control.offset_left = -size.x / 2.0
			control.offset_right = size.x / 2.0
			control.offset_top = -size.y / 2.0
			control.offset_bottom = size.y / 2.0
		, CONNECT_ONE_SHOT)

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _on_continue_pressed() -> void:
	_display_options_view.close()
	_save_load_view.open()

func _on_load_requested(campaign_name: String, slot_name: String) -> void:
	GameLaunchState.request_load(campaign_name, slot_name)
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _on_display_options_pressed() -> void:
	_save_load_view.close()
	_display_options_view.open()

func _on_exit_pressed() -> void:
	get_tree().quit()
