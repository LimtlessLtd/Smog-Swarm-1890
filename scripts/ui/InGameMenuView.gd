class_name InGameMenuView
extends Panel

## In-game pause/menu hub (playtest round 6, user request: "There should
## be a 'Main Menu' that has all the save/load functionality on it... put
## [display options] as options on the main menu... remove them from the
## main screen") — replaces MainHUD's old always-visible top-right
## "Quick Save"/"Quick Load"/"Browse Saves..."/"Display..." buttons with a
## single "Menu" button that opens this hub instead. Deliberately a dumb
## signal-emitting view, same convention as SaveLoadView/DisplayOptionsView
## — MainHUD still owns the actual Save/Load/Display panels and the scene
## changes (Quit to Main Menu / Exit), this class just asks for them.
## Fourth centered toggleable panel to follow SaveLoadView's own
## established shape (get_content_min_size()/open()/close()).

signal save_load_requested
signal display_options_requested
signal resume_requested
signal quit_to_menu_requested
signal exit_requested

var _layout: VBoxContainer

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "Menu"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	_layout.add_child(_row_button("Resume", func() -> void:
		resume_requested.emit()
		close()
	))
	_layout.add_child(_row_button("Save / Load...", func() -> void:
		save_load_requested.emit()
		close()
	))
	_layout.add_child(_row_button("Display Options...", func() -> void:
		display_options_requested.emit()
		close()
	))
	_layout.add_child(_row_button("Quit to Main Menu", func() -> void:
		quit_to_menu_requested.emit()
	))
	_layout.add_child(_row_button("Exit to Desktop", func() -> void:
		exit_requested.emit()
	))

## Same content-driven sizing every other centered panel here already uses
## — see SaveLoadView.get_content_min_size()'s own doc comment.
func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func open() -> void:
	visible = true

func close() -> void:
	visible = false

func _row_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	HUDStyles.style_button(button)
	return button
