class_name BuildMenuView
extends Control

## Build menu (design doc Phase 6.1 — "the actual UI for
## BuildingManager.place_building_at_world(), built in Phase 2.5, never
## called by anything since"). One button per BuildingCatalog definition,
## grouped into a tab per category; pressing one arms placement mode by
## emitting building_selected. This view only knows about *selecting* a
## type — it has no idea what a hex or a world position is;
## BuildPlacementController (Phase 6.1, `/scripts/world`) is what turns a
## selection into an actual placed building.
##
## **Tabbed, not one long scrolling list** (user report/request): the
## original single VBoxContainer under one ScrollContainer worked but grew
## to five-plus screens of vertical scrolling once every category was
## authored, and buried DEFENSE_WORKS entirely (see below) below the fold
## with no visual grouping. A TabContainer — one tab per
## GameEnums.BuildingCategory, unchanged category order — replaces it;
## each tab keeps its own ScrollContainer+VBoxContainer in case a category
## itself ever grows long enough to need scrolling, but no longer forces
## scrolling PAST other categories to reach one.
##
## **DEFENSE_WORKS is now included** — CATEGORY_ORDER previously omitted it
## entirely, which meant Searchlight Tower (a normal, fully-placeable
## building) had no click path to it at all despite being fully
## implemented, found during a real playtest. Ditch/Oil Pit stay excluded
## (see _EXCLUDED_FROM_MENU below) — they're real BuildingCatalog entries
## for their cost data only; WallManager.add_defense_work() is their actual
## placement path, not this menu.

signal building_selected(building_type: GameEnums.BuildingType)
## Real bug fixed (player report: walls "are not free hand to place/draw"
## — a project-wide grep confirmed there was never ANY placement UI for
## walls at all, not merely a hex-locked one; every wall a player has ever
## seen was the free starting perimeter). A fourth tab, own signal rather
## than reusing building_selected — arming WallPlacementController's
## click-DRAG flow is a different shape from BuildPlacementController's
## click-to-place one, not a building type.
signal wall_placement_selected(is_gate: bool)

const CATEGORY_ORDER: Array[GameEnums.BuildingCategory] = [
	GameEnums.BuildingCategory.HOUSING_CIVIL,
	GameEnums.BuildingCategory.INDUSTRY_EXTRACTION,
	GameEnums.BuildingCategory.AGRICULTURE,
	GameEnums.BuildingCategory.DEFENSE_WORKS,
]

## Ditch/Oil Pit are DEFENSE_WORKS BuildingCatalog entries but are placed
## via WallManager.add_defense_work() on an existing wall segment, not
## BuildingManager.place_building_at_world() like everything else this menu
## arms — see WallManager's own class doc comment ("deliberately NOT placed
## through BuildingManager.place_building()"). Excluded here so clicking one
## can't arm a placement flow that was never built to handle it.
const _EXCLUDED_FROM_MENU: Array[GameEnums.BuildingType] = [
	GameEnums.BuildingType.DITCH,
	GameEnums.BuildingType.OIL_PIT,
]

func _ready() -> void:
	custom_minimum_size = Vector2(320, 300)
	HUDStyles.style_panel(self)

	var tabs := TabContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	HUDStyles.style_tab_container(tabs)
	add_child(tabs)

	for category in CATEGORY_ORDER:
		var definitions := _visible_definitions(category)
		if definitions.is_empty():
			continue  # An empty tab (e.g. every entry filtered out) would just be a dead click target.
		tabs.add_child(_build_tab(category, definitions))

	tabs.add_child(_build_wall_tab())

## Real placement UI for walls (see wall_placement_selected's own doc
## comment) — deliberately just two buttons, not a per-tier list the way
## buildings get one: WallManager.place_wall_line() only ever places fresh
## Wooden segments (upgrade_segment(), reached by selecting an existing
## wall, is still the only way to a Brick/Concrete tier — unchanged from
## before this rework), so a tier picker here would offer choices that
## don't actually exist yet. "Gate" is the same Wooden segment/cost, just
## intrinsically weaker (WallSegment.is_gate's own doc comment) — a
## deliberate weak point the player places on purpose, not a difference
## the build menu needs to price separately.
func _build_wall_tab() -> Control:
	var container := Control.new()
	container.name = "Walls"  # TabContainer reads a child's own `name` as its tab label.

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	container.add_child(list)

	var hint := Label.new()
	hint.text = "Click and drag along the map to draw a wall — a long drag auto-splits into short, independently-defended pieces."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	HUDStyles.style_label(hint)
	list.add_child(hint)

	var wall_button := Button.new()
	wall_button.text = "Wooden Wall"
	wall_button.tooltip_text = _format_cost(WallCatalog.get_build_cost(WallCatalog.WOODEN)) + " (per hex-edge-length drawn)"
	wall_button.pressed.connect(_on_wall_button_pressed.bind(false))
	HUDStyles.style_button(wall_button)
	list.add_child(wall_button)

	var gate_button := Button.new()
	gate_button.text = "Gate"
	gate_button.tooltip_text = "Same cost as a Wooden Wall, deliberately weaker (a fortification's traditional weak point)."
	gate_button.pressed.connect(_on_wall_button_pressed.bind(true))
	HUDStyles.style_button(gate_button)
	list.add_child(gate_button)

	return container

func _on_wall_button_pressed(is_gate: bool) -> void:
	wall_placement_selected.emit(is_gate)

func _build_tab(category: GameEnums.BuildingCategory, definitions: Array[BuildingDefinition]) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = _category_name(category)  # TabContainer reads a child's own `name` as its tab label.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## No dialog should ever need a horizontal scrollbar — button text wraps/fits within the panel's own width instead.

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for definition in definitions:
		var button := Button.new()
		button.text = definition.display_name
		# Full cost as a hover tooltip rather than inline text — cost
		# strings ("Church Steeple Watchtower: 100 Bricks, 10 Cast
		# Iron") run too long to fit the panel alongside the name.
		button.tooltip_text = _format_cost(definition.construction_cost)
		button.pressed.connect(_on_building_button_pressed.bind(definition.building_type))
		HUDStyles.style_button(button)
		list.add_child(button)

	return scroll

func _visible_definitions(category: GameEnums.BuildingCategory) -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for definition in BuildingCatalog.get_definitions_in_category(category):
		if not _EXCLUDED_FROM_MENU.has(definition.building_type):
			result.append(definition)
	return result

func _on_building_button_pressed(building_type: GameEnums.BuildingType) -> void:
	building_selected.emit(building_type)

func _category_name(category: GameEnums.BuildingCategory) -> String:
	match category:
		GameEnums.BuildingCategory.HOUSING_CIVIL:
			return "Housing & Civil"
		GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
			return "Industry & Extraction"
		GameEnums.BuildingCategory.AGRICULTURE:
			return "Agriculture"
		GameEnums.BuildingCategory.DEFENSE_WORKS:
			return "Defense Works"
		_:
			return "Other"

func _format_cost(cost: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in cost:
		if not first:
			text += ", "
		text += "%d %s" % [int(cost[resource_type]), ResourceVisuals.display_name(resource_type)]
		first = false
	return text
