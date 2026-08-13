class_name SaveLoadView
extends Panel

## The Save/Load UI — a campaign-name field, a clickable browser of
## existing campaigns, a slot-name field, and a clickable browser of
## existing slots within whichever campaign is currently typed. The
## underlying SaveLoadManager.save_game()/load_game()/get_campaign_names()/
## get_slot_names() API supports exactly this.
##
## Same "dumb display component, doesn't own logic" convention every other
## HUD view here follows: doesn't call SaveLoadManager directly — emits
## save_requested/load_requested and lets MainHUD do that, exactly like
## BuildMenuView.building_selected/UnitPanelView's own button signals.
## Feedback (saved/loaded/failed) reuses MainHUD's existing toast, driven
## off SaveLoadManager's own signals it's already listening to — this view
## doesn't need a second feedback mechanism.
##
## Hidden by default — the first TOGGLEABLE panel in this HUD (every other
## view here is always visible in its own corner). `open()`/`close()` own
## that visibility; a "Browse Saves..." button next to the existing Quick
## Save/Load pair is MainHUD's own trigger for `open()`.

signal save_requested(campaign_name: String, slot_name: String)
signal load_requested(campaign_name: String, slot_name: String)
signal closed

const LIST_HEIGHT := 90.0

var _save_load_manager: SaveLoadManager
var _campaign_edit: LineEdit
var _campaign_list: VBoxContainer
var _slot_edit: LineEdit
var _slot_list: VBoxContainer
var _layout: VBoxContainer
var _save_button: Button

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "Save / Load"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	_campaign_edit = _build_labeled_edit(_layout, "Campaign:", "Campaign name")
	_campaign_edit.text_changed.connect(_on_campaign_text_changed)
	_campaign_list = _build_list(_layout)

	_slot_edit = _build_labeled_edit(_layout, "Slot:", "Slot name")
	_slot_list = _build_list(_layout)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_layout.add_child(buttons)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_on_save_pressed)
	HUDStyles.style_button(_save_button)
	buttons.add_child(_save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	HUDStyles.style_button(load_button)
	buttons.add_child(load_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	HUDStyles.style_button(close_button)
	buttons.add_child(close_button)

## MainHUD's own `_place_center()` reads this to size the panel to its real
## content instead of trusting a hand-picked constant — see
## DisplayOptionsView.get_content_min_size()'s own doc comment for why
## (same reasoning, same pattern, third panel to follow it).
func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func setup(save_load_manager: SaveLoadManager) -> void:
	_save_load_manager = save_load_manager

## MainMenuView's boot-screen "Continue" browser reuses this same view for
## Load, but there's no live game to save FROM there — hides the Save
## button entirely rather than leaving a dead button that would silently
## do nothing. MainHUD's own in-game instance never calls this, so it
## keeps Save visible.
func set_save_enabled(enabled: bool) -> void:
	_save_button.visible = enabled

## Re-scans disk for campaigns/slots every time — cheap (a directory
## listing, via `get_campaign_names()`/`get_slot_names()`), and means a
## save made just now (or by hand-editing `user://saves/`) always
## shows up next time this opens rather than needing its own live-refresh
## wiring for a rarely-open dialog.
func open() -> void:
	visible = true
	_refresh_campaigns()

func close() -> void:
	visible = false
	closed.emit()

func _build_labeled_edit(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(70, 0)
	HUDStyles.style_label(label)
	row.add_child(label)

	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Godot's LineEdit doesn't factor its own placeholder text into its
	# minimum size — found after MainHUD's own auto-sizing fix (see
	# get_content_min_size()'s doc comment) made this panel shrink to fit
	# its now-accurately-measured content, which left the field only as
	# wide as LineEdit's tiny engine default and clipped "Campaign name"/
	# "Slot name" down to "Campaig"/"Slot nam". An explicit floor here is
	# what the old hand-picked SAVE_LOAD_VIEW_SIZE constant used to give it
	# by accident, made deliberate now that nothing else provides it.
	edit.custom_minimum_size = Vector2(160, 0)
	row.add_child(edit)
	return edit

func _build_list(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## No dialog should ever need a horizontal scrollbar — see TechTreeView's own note on this.
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _refresh_campaigns() -> void:
	for child in _campaign_list.get_children():
		child.queue_free()
	if not _save_load_manager:
		return
	for campaign_name in _save_load_manager.get_campaign_names():
		var button := Button.new()
		button.text = campaign_name
		button.pressed.connect(_on_campaign_button_pressed.bind(campaign_name))
		HUDStyles.style_button(button)
		_campaign_list.add_child(button)
	_refresh_slots()

func _refresh_slots() -> void:
	for child in _slot_list.get_children():
		child.queue_free()
	if not _save_load_manager or _campaign_edit.text.is_empty():
		return
	for slot_name in _save_load_manager.get_slot_names(_campaign_edit.text):
		var button := Button.new()
		button.text = slot_name
		button.pressed.connect(_on_slot_button_pressed.bind(slot_name))
		HUDStyles.style_button(button)
		_slot_list.add_child(button)

func _on_campaign_button_pressed(campaign_name: String) -> void:
	_campaign_edit.text = campaign_name
	_refresh_slots()

func _on_slot_button_pressed(slot_name: String) -> void:
	_slot_edit.text = slot_name

func _on_campaign_text_changed(_new_text: String) -> void:
	_refresh_slots()

func _on_save_pressed() -> void:
	if _campaign_edit.text.is_empty() or _slot_edit.text.is_empty():
		return
	save_requested.emit(_campaign_edit.text, _slot_edit.text)
	_refresh_campaigns()  # A brand-new campaign/slot just got written — reflect it immediately.

func _on_load_pressed() -> void:
	if _campaign_edit.text.is_empty() or _slot_edit.text.is_empty():
		return
	load_requested.emit(_campaign_edit.text, _slot_edit.text)
