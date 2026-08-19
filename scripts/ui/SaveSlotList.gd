class_name SaveSlotList
extends ScrollContainer

## Scrolling list of one campaign's save slots — thumbnail, slot name, and
## when it was written. Shared by both places a player picks a save: the
## in-game Save/Load panel (SaveLoadView) and the boot screen's campaign
## browser (CampaignBrowserView), which reach it through the same
## setup()/show_campaign() pair.
##
## A dumb display component like every other view here: emits
## slot_selected and lets its owner decide what a click means (fill the
## slot field, or load immediately).

signal slot_selected(slot_name: String)

## Three rows of HUDStyles.build_thumbnail_row() at its default thumbnail
## height, exactly: 3 * (72 + 6 + 6) + 2 * 4 separation. Sized to whole rows
## because a partial row cut off flush against the panel's own bottom edge
## reads as clipped content rather than as more list below.
const LIST_HEIGHT: float = 260.0
const LIST_WIDTH: float = 300.0

var _save_load_manager: SaveLoadManager
var _column: VBoxContainer
var _campaign_name: String = ""

func _ready() -> void:
	# Default only — an owner that wants a different size (CampaignBrowserView
	# matches this list's height to the campaign list it swaps with) sets
	# custom_minimum_size itself and is not overwritten here.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## No dialog should ever need a horizontal scrollbar — see TechTreeView's own note on this.
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)
	# show_campaign() is callable before this node enters the tree (an owner
	# that configures its children right after new()), so a campaign set
	# that early is held and drawn here instead of being silently dropped.
	_rebuild()

func setup(save_load_manager: SaveLoadManager) -> void:
	_save_load_manager = save_load_manager

## Re-scans disk every call, same reasoning SaveLoadView's own refresh
## documents: a directory listing is cheap, and a save made moments ago
## must show up without this needing live-refresh wiring of its own.
func show_campaign(campaign_name: String) -> void:
	_campaign_name = campaign_name
	_rebuild()

func _rebuild() -> void:
	if _column == null:
		return
	for child in _column.get_children():
		child.queue_free()
	if _save_load_manager == null or _campaign_name.is_empty():
		return

	var slot_names := _save_load_manager.get_slot_names(_campaign_name)
	if slot_names.is_empty():
		var empty := Label.new()
		empty.text = "No saves in this campaign yet."
		HUDStyles.style_label(empty, false, true)
		_column.add_child(empty)
		return

	# Newest first, not the alphabetical order get_slot_names() returns: the
	# save a player wants back is almost always the most recent one.
	slot_names.sort_custom(func(a: String, b: String) -> bool:
		return _save_load_manager.get_slot_modified_time(_campaign_name, a) \
			> _save_load_manager.get_slot_modified_time(_campaign_name, b))

	for slot_name in slot_names:
		var row := HUDStyles.build_thumbnail_row(
			slot_name,
			SaveTimeFormat.describe(_save_load_manager.get_slot_modified_time(_campaign_name, slot_name)),
			_save_load_manager.get_slot_thumbnail(_campaign_name, slot_name),
			func() -> void: slot_selected.emit(slot_name))
		_column.add_child(row)
