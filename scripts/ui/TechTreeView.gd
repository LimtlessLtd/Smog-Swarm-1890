class_name TechTreeView
extends Panel

## The Tech Tree screen. TechManager's own get_research_error()/
## can_start_research() API was written with this exact screen in mind —
## mirrors BuildingManager.get_placement_error()'s "queryable without side
## effects" pattern so this screen can preview legality.
##
## Same "dumb display component, doesn't own logic" convention every other
## HUD view here follows: reads TechManager directly for display (a
## read-only query, same as UnitPanelView reading
## UnitManager.get_training_error() for a button's disabled/tooltip state),
## but the one real mutation — actually starting research — goes out as
## research_requested for MainHUD to forward, never called on TechManager
## directly from here.
##
## Hidden by default, toggled open/closed — same convention SaveLoadView follows.

signal research_requested(tech_id: StringName)
signal closed

const LIST_HEIGHT := 280.0

## Declaration order groups related nodes together (both wall tiers, then
## every unit tier in order, then Seafaring standing alone) rather than
## TechCatalog's own dictionary iteration order, which isn't guaranteed
## stable across runs the way a hand-authored list is.
const DISPLAY_ORDER: Array[StringName] = [
	&"brick_walls", &"concrete_walls",
	&"unit_tier_1", &"unit_tier_2", &"unit_tier_3", &"unit_tier_4", &"unit_tier_5",
	&"seafaring",
]

var _tech_manager: TechManager
var _list: VBoxContainer
var _layout: VBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "Technology"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## Without this, description text runs off the right edge into a horizontal scrollbar instead of wrapping — disabling horizontal scroll forces children to respect this container's width, which is what makes autowrap_mode below work at all.
	_layout.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	HUDStyles.style_button(close_button)
	_layout.add_child(close_button)

## MainHUD's own `_place_center()` reads this to size the panel to its real
## content instead of trusting a hand-picked constant — see
## DisplayOptionsView.get_content_min_size()'s own doc comment for why
## (same reasoning, same pattern). Unlike that panel, `_scroll`'s own
## LIST_HEIGHT is intentionally fixed (the tech list can outgrow the panel
## by design — that's what the internal scrollbar is for), so this reports
## _layout's minimum size AS IF _scroll only needed LIST_HEIGHT, not its
## potentially-much-taller full content — get_combined_minimum_size()
## already does exactly that for a ScrollContainer with a custom_minimum_size
## set, so no special-casing is needed here beyond just asking _layout.
func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func setup(tech_manager: TechManager) -> void:
	_tech_manager = tech_manager
	if _tech_manager:
		_tech_manager.research_started.connect(_on_tech_state_changed)
		_tech_manager.research_progress_changed.connect(_on_tech_state_changed)
		_tech_manager.tech_researched.connect(_on_tech_state_changed)

func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false
	closed.emit()

## Re-derives every row from scratch on any research state change — cheap
## (8 nodes total, same "small enough to just rebuild" reasoning
## SaveLoadView's own campaign/slot browser already leans on) and means a
## day ticking by (research_progress_changed) or another system's own
## start_research() call (there isn't one today, but nothing rules it out)
## can't leave this panel showing a stale days-remaining count while open.
func _on_tech_state_changed(_tech_id: StringName = &"", _a: int = 0, _b: int = 0) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if not _tech_manager:
		return
	for tech_id in DISPLAY_ORDER:
		var definition := TechCatalog.get_definition(tech_id)
		if definition:
			_list.add_child(_build_row(definition))

func _build_row(definition: TechDefinition) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = definition.display_name
	HUDStyles.style_label(header, true)
	row.add_child(header)

	var description := Label.new()
	description.text = definition.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDStyles.style_label(description, false, true)
	row.add_child(description)

	var status := Label.new()
	status.text = _status_text(definition)
	HUDStyles.style_label(status, false, true)
	row.add_child(status)

	var button := Button.new()
	var is_researched := _tech_manager.is_researched(definition.tech_id)
	var is_active := _tech_manager.get_active_tech() == definition.tech_id
	if is_researched:
		button.text = "Researched"
		button.disabled = true
	elif is_active:
		button.text = "Researching..."
		button.disabled = true
	else:
		button.text = "Research (%s)" % _format_cost(definition.cost)
		var error := _tech_manager.get_research_error(definition.tech_id)
		button.disabled = not error.is_empty()
		button.tooltip_text = error
		button.pressed.connect(_on_research_pressed.bind(definition.tech_id))
	HUDStyles.style_button(button)
	row.add_child(button)

	return row

## Shown alongside (not instead of) the button's own cost/tooltip — a plain
## sentence covering the three states a bare disabled button can't convey by
## itself: prerequisites still owed, research_days once it starts, and the
## Seafaring-specific campaign gate.
func _status_text(definition: TechDefinition) -> String:
	if _tech_manager.is_researched(definition.tech_id):
		return "Researched."
	if _tech_manager.get_active_tech() == definition.tech_id:
		return "%d of %d days remaining." % [_tech_manager.get_days_remaining(), definition.research_days]
	if not definition.prerequisites.is_empty():
		var names: Array[String] = []
		for prereq_id in definition.prerequisites:
			var prereq_definition := TechCatalog.get_definition(prereq_id)
			names.append(prereq_definition.display_name if prereq_definition else String(prereq_id))
		return "Requires: %s. Takes %d days once started." % [", ".join(names), definition.research_days]
	return "Takes %d days once started." % definition.research_days

func _on_research_pressed(tech_id: StringName) -> void:
	research_requested.emit(tech_id)

func _format_cost(cost: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in cost:
		if not first:
			text += ", "
		text += "%d %s" % [int(cost[resource_type]), ResourceVisuals.display_name(resource_type)]
		first = false
	return text
