class_name NewCampaignView
extends Panel

## Names a campaign before it starts — "when you create a campaign, you
## choose the name of the campaign at that point" (user request). The boot
## screen's "New Game" opens this instead of dropping straight into
## Main.tscn, so every save the session goes on to write already has a
## campaign to belong to.
##
## A dumb display component like every other view here: emits
## campaign_confirmed and lets MainMenuView do the GameLaunchState handoff
## and the scene change.
##
## Existing campaign names are listed rather than rejected. Reusing one is
## legitimate — a second run at the same campaign lands its saves in the
## same folder — but a player who typed a name they already have should be
## able to SEE that before starting, which a bare text field can't show.

signal campaign_confirmed(campaign_name: String)
signal closed

const DEFAULT_NAME: String = "Manchester Campaign"
const EXISTING_LIST_HEIGHT: float = 90.0

var _save_load_manager: SaveLoadManager
var _layout: VBoxContainer
var _name_edit: LineEdit
var _existing_column: VBoxContainer
var _existing_label: Label

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "New Campaign"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	var prompt := Label.new()
	prompt.text = "Name this campaign. Every save you make will be filed under it."
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(300, 0)  ## An autowrap Label with no width to wrap against reports a degenerate minimum size — see HUDStyles.build_card()'s own note.
	HUDStyles.style_label(prompt, false, true)
	_layout.add_child(prompt)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Campaign name"
	_name_edit.custom_minimum_size = Vector2(300, 0)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_start_pressed())
	_layout.add_child(_name_edit)

	_existing_label = Label.new()
	_existing_label.text = "Existing campaigns:"
	HUDStyles.style_label(_existing_label, false, true)
	_layout.add_child(_existing_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, EXISTING_LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layout.add_child(scroll)
	_existing_column = VBoxContainer.new()
	_existing_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_existing_column)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_layout.add_child(buttons)

	var start_button := Button.new()
	start_button.text = "Start"
	start_button.pressed.connect(_on_start_pressed)
	HUDStyles.style_button(start_button)
	buttons.add_child(start_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(close)
	HUDStyles.style_button(cancel_button)
	buttons.add_child(cancel_button)

func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func setup(save_load_manager: SaveLoadManager) -> void:
	_save_load_manager = save_load_manager

func open() -> void:
	visible = true
	_name_edit.text = DEFAULT_NAME
	_name_edit.select_all()
	_name_edit.grab_focus()
	_refresh_existing()

func close() -> void:
	visible = false
	closed.emit()

func _refresh_existing() -> void:
	for child in _existing_column.get_children():
		child.queue_free()
	var names: Array[String] = []
	if _save_load_manager != null:
		names = _save_load_manager.get_campaign_names()
	_existing_label.visible = not names.is_empty()
	for campaign_name in names:
		var label := Label.new()
		label.text = "• %s" % campaign_name
		label.clip_text = true
		HUDStyles.style_label(label, false, true)
		_existing_column.add_child(label)

func _on_start_pressed() -> void:
	var campaign_name := _name_edit.text.strip_edges()
	if campaign_name.is_empty():
		return
	campaign_confirmed.emit(campaign_name)
	close()
