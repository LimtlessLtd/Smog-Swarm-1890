class_name SaveLoadView
extends Panel

## The in-game Save/Load panel: which campaign is being played, a slot-name
## field, and a browser of that campaign's existing saves.
##
## Scoped to ONE campaign, with no way to reach another — "when you save
## games, they are all saved under that campaign that you are playing...
## and when you load games from within a campaign, it only shows you saves
## from that campaign" (user request). The campaign is chosen once, when
## it is created, on the boot screen; there is deliberately no campaign
## field here to type a different one into. Crossing campaigns is the boot
## screen's job (CampaignBrowserView), because it means starting a
## different game, not loading a slot in this one.
##
## Same "dumb display component, doesn't own logic" convention every other
## HUD view here follows: doesn't call SaveLoadManager to save or load —
## emits save_requested/load_requested and lets MainHUD do that, exactly
## like BuildMenuView.building_selected/UnitPanelView's own button signals.
## It does READ SaveLoadManager (the campaign name, and the slot list via
## SaveSlotList), which is a query, not a state change. Feedback
## (saved/loaded/failed) reuses MainHUD's existing toast, driven off
## SaveLoadManager's own signals it's already listening to — this view
## doesn't need a second feedback mechanism.
##
## Hidden by default — one of the four toggleable centered panels
## (HUDPanelSwitcher). `open()`/`close()` own that visibility; the in-game
## menu's "Save / Load..." row is its trigger.

signal save_requested(slot_name: String)
signal load_requested(slot_name: String)
signal closed

var _save_load_manager: SaveLoadManager
var _campaign_label: Label
var _slot_edit: LineEdit
var _slot_list: SaveSlotList
var _layout: VBoxContainer

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

	_campaign_label = Label.new()
	_campaign_label.clip_text = true
	HUDStyles.style_label(_campaign_label, false, true)
	_layout.add_child(_campaign_label)

	_slot_edit = _build_labeled_edit(_layout, "Slot:", "Slot name")

	_slot_list = SaveSlotList.new()
	_slot_list.name = "SaveSlotList"
	_layout.add_child(_slot_list)
	_slot_list.slot_selected.connect(_on_slot_selected)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_layout.add_child(buttons)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	HUDStyles.style_button(save_button)
	buttons.add_child(save_button)

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
## DisplayOptionsView.get_content_min_size()'s own doc comment for why.
func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func setup(save_load_manager: SaveLoadManager) -> void:
	_save_load_manager = save_load_manager
	_slot_list.setup(save_load_manager)

## Re-reads the campaign and re-scans its slots every time this opens —
## cheap (a directory listing), and means a save made just now always shows
## up next time this opens rather than needing its own live-refresh wiring
## for a rarely-open dialog.
func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if _save_load_manager == null:
		return
	var campaign := _save_load_manager.get_active_campaign()
	_campaign_label.text = "Campaign: %s" % campaign
	_slot_list.show_campaign(campaign)

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
	# wide as LineEdit's tiny engine default and clipped "Slot name" down
	# to "Slot nam". An explicit floor here is what the old hand-picked
	# SAVE_LOAD_VIEW_SIZE constant used to give it by accident, made
	# deliberate now that nothing else provides it.
	edit.custom_minimum_size = Vector2(160, 0)
	row.add_child(edit)
	return edit

## Fills the field rather than loading immediately: clicking a slot is how
## a player picks which one to OVERWRITE as well as which to load, and a
## list where one click silently discards the running game would be a trap.
func _on_slot_selected(slot_name: String) -> void:
	_slot_edit.text = slot_name

func _on_save_pressed() -> void:
	if _slot_edit.text.strip_edges().is_empty():
		return
	save_requested.emit(_slot_edit.text.strip_edges())
	# Closes on save, for the same reason the screenshot hides the HUD:
	# leaving the panel up over the shot the player just took of the map
	# behind it is the wrong feedback. MainHUD's toast confirms the write.
	close()

func _on_load_pressed() -> void:
	if _slot_edit.text.strip_edges().is_empty():
		return
	load_requested.emit(_slot_edit.text.strip_edges())
	close()
