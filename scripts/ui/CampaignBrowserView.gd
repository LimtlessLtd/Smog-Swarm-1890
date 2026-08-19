class_name CampaignBrowserView
extends Panel

## The boot screen's Load Game browser: campaigns first, then that
## campaign's saves — "When you load games from the main menu, it first
## shows you the campaigns available, and then when you select a campaign,
## it will show you the campaign saves available" (user request).
##
## Two states in one panel rather than two panels, because it is one
## drill-down: pick a campaign, pick a slot inside it, or go back. The slot
## half is SaveSlotList, the same widget the in-game Save/Load panel uses,
## so a save looks identical in both places.
##
## Each campaign is shown with its most recent save's screenshot
## (SaveLoadManager.get_campaign_thumbnail()) — the picture the player
## should recognise a campaign by is the furthest they actually got in it,
## not its first save.
##
## Boot screen only. It does NOT load anything itself: MainMenu.tscn has no
## live managers to restore state into, so this emits load_requested and
## MainMenuView records it on GameLaunchState and changes scene (see that
## autoload's own doc comment for the full handoff). The in-game panel
## deliberately has no equivalent — switching campaign mid-game means
## starting a different game, which is what coming back to this screen is.

signal load_requested(campaign_name: String, slot_name: String)
signal closed

## Three rows of HUDStyles.build_thumbnail_row() at its default thumbnail
## height, exactly: 3 * (72 + 6 + 6) + 2 * 4 separation. A height that cuts
## a row in half at the panel's own bottom edge reads as a clipped layout
## rather than as a scrollable list.
const LIST_HEIGHT: float = 260.0
## Wide enough for a campaign row's full subtitle ("3 saves · last played
## 2026-08-19 14:25") beside its 128 px thumbnail. Measured, not guessed:
## at 340 the date clipped mid-way through the year — those subtitles are
## clip_text, so a list too narrow truncates silently instead of wrapping.
const LIST_WIDTH: float = 430.0

var _save_load_manager: SaveLoadManager
var _layout: VBoxContainer
var _subtitle: Label
var _campaign_scroll: ScrollContainer
var _campaign_column: VBoxContainer
var _slot_list: SaveSlotList
var _back_button: Button
var _selected_campaign: String = ""

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "Load Game"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	_subtitle = Label.new()
	_subtitle.clip_text = true
	HUDStyles.style_label(_subtitle, false, true)
	_layout.add_child(_subtitle)

	_campaign_scroll = ScrollContainer.new()
	_campaign_scroll.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	_campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layout.add_child(_campaign_scroll)
	_campaign_column = VBoxContainer.new()
	_campaign_column.add_theme_constant_override("separation", 4)
	_campaign_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_scroll.add_child(_campaign_column)

	_slot_list = SaveSlotList.new()
	_slot_list.name = "SaveSlotList"
	# Same size as the campaign list it swaps with, set BEFORE add_child so
	# SaveSlotList's own default never applies: this panel is sized to its
	# content ONCE (MainMenuView._place_center()'s one-shot measurement), so
	# two states of different heights would leave one of them clipped or
	# floating in dead space.
	_slot_list.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	# Hidden from the moment it is built, not just from open(): a
	# BoxContainer excludes hidden children from its minimum size, and
	# MainMenuView._place_center() measures this panel ONE frame after
	# construction. With both states visible at that instant the panel sized
	# itself to hold them stacked and opened with an empty half-screen of
	# dead space below its buttons.
	_slot_list.visible = false
	_layout.add_child(_slot_list)
	_slot_list.slot_selected.connect(_on_slot_selected)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_layout.add_child(buttons)

	_back_button = Button.new()
	_back_button.text = "< Campaigns"
	_back_button.pressed.connect(_show_campaigns)
	HUDStyles.style_button(_back_button)
	buttons.add_child(_back_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	HUDStyles.style_button(close_button)
	buttons.add_child(close_button)

func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func setup(save_load_manager: SaveLoadManager) -> void:
	_save_load_manager = save_load_manager
	_slot_list.setup(save_load_manager)

## Always opens on the campaign list, never on whichever campaign was last
## drilled into — reopening this is how a player changes their mind about
## which game to continue.
func open() -> void:
	visible = true
	_show_campaigns()

func close() -> void:
	visible = false
	closed.emit()

func _show_campaigns() -> void:
	_selected_campaign = ""
	_campaign_scroll.visible = true
	_slot_list.visible = false
	_back_button.visible = false
	_rebuild_campaigns()

func _show_slots(campaign_name: String) -> void:
	_selected_campaign = campaign_name
	_campaign_scroll.visible = false
	_slot_list.visible = true
	_back_button.visible = true
	_subtitle.text = campaign_name
	_slot_list.show_campaign(campaign_name)

func _rebuild_campaigns() -> void:
	for child in _campaign_column.get_children():
		child.queue_free()
	if _save_load_manager == null:
		return

	var campaign_names := _save_load_manager.get_campaign_names()
	if campaign_names.is_empty():
		_subtitle.text = "No campaigns saved yet."
		var empty := Label.new()
		empty.text = "Start a New Game to create one."
		HUDStyles.style_label(empty, false, true)
		_campaign_column.add_child(empty)
		return

	_subtitle.text = "Choose a campaign"
	# Most recently played first — the same ordering, and the same reason,
	# SaveSlotList applies to slots within a campaign.
	campaign_names.sort_custom(func(a: String, b: String) -> bool:
		return _latest_time(a) > _latest_time(b))

	for campaign_name in campaign_names:
		var slot_count := _save_load_manager.get_slot_names(campaign_name).size()
		var subtitle := "%d save%s" % [slot_count, "" if slot_count == 1 else "s"]
		var latest := SaveTimeFormat.describe(_latest_time(campaign_name))
		if not latest.is_empty():
			subtitle += "  ·  last played %s" % latest
		var row := HUDStyles.build_thumbnail_row(
			campaign_name,
			subtitle,
			_save_load_manager.get_campaign_thumbnail(campaign_name),
			func() -> void: _show_slots(campaign_name))
		_campaign_column.add_child(row)

func _latest_time(campaign_name: String) -> int:
	var latest := _save_load_manager.get_latest_slot_name(campaign_name)
	if latest.is_empty():
		return 0
	return _save_load_manager.get_slot_modified_time(campaign_name, latest)

## One click loads, unlike the in-game panel's own slot list — there is no
## running game here for it to discard, and picking a save IS the action
## this screen exists for.
func _on_slot_selected(slot_name: String) -> void:
	if _selected_campaign.is_empty():
		return
	load_requested.emit(_selected_campaign, slot_name)
