class_name BuildMenuView
extends PanelContainer

## Build menu (design doc Phase 6.1 — "the actual UI for
## BuildingManager.place_building_at_world(), built in Phase 2.5, never
## called by anything since"). One card per BuildingCatalog definition,
## grouped into a column per category; clicking one arms placement mode by
## emitting building_selected. This view only knows about *selecting* a
## type — it has no idea what a hex or a world position is;
## BuildPlacementController (Phase 6.1, `/scripts/world`) is what turns a
## selection into an actual placed building.
##
## **All categories visible at once, no tabs (user request, playtest round
## 4: "too many clicks having to scroll to the right tab, just display all
## the tabs all the time")** — the previous `TabContainer` (one category
## hidden behind another until clicked) is gone; every category is now its
## own always-visible column (header + a row of building cards) inside one
## horizontally-scrolling strip. Nothing is hidden behind a click anymore —
## "scrolling" sideways to reach a category some categories to the right
## replaces "clicking a tab", which is the actual complaint (extra clicks),
## not scrolling itself.
##
## **Cards, not bare-text buttons (user request: "display the pictures of
## the building... how much each building costs, the upkeep it requires,
## and what it actually does")** — each card shows the building's real art
## (BuildingVisuals.building_texture(), same texture TacticalHexView
## renders), its name, and a compact cost/upkeep/effect summary, all
## visible without hovering (a tooltip was the OLD cost-only convention;
## this pass makes the same information a first-class part of the card
## instead of hiding it behind a hover).
##
## **Merged into one bottom bar with the minimap (user request, #5)** — this
## view no longer positions or sizes itself (MainHUD._build_bottom_bar()
## does, sizing it to SIZE_EXPAND_FILL alongside a fixed-width MinimapView
## in the same row) or draws its own background via a bare `Control`
## (that never actually rendered anything — see the dark-background note
## below); it now extends `PanelContainer` so `HUDStyles.style_panel()`
## genuinely draws a background, same fix `ResourceBarView` needed for the
## same reason (only `Panel`/`PanelContainer` actually draw a `"panel"`
## theme stylebox — a plain `Control` silently ignores one).

signal building_selected(building_type: GameEnums.BuildingType)
## Real bug fixed (player report: walls "are not free hand to place/draw"
## — a project-wide grep confirmed there was never ANY placement UI for
## walls at all, not merely a hex-locked one; every wall a player has ever
## seen was the free starting perimeter). A fourth column, own signal rather
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
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDStyles.style_panel(self)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  ## The whole point of this rework — sideways scrolling replaces tab-clicking, see class doc.
	add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	scroll.add_child(columns)

	for category in CATEGORY_ORDER:
		var definitions := _visible_definitions(category)
		if definitions.is_empty():
			continue  # An empty column would just be dead space.
		columns.add_child(_build_category_column(category, definitions))

	columns.add_child(_build_wall_column())

func _build_category_column(category: GameEnums.BuildingCategory, definitions: Array[BuildingDefinition]) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = _category_name(category)
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for definition in definitions:
		row.add_child(_build_building_card(definition))
	column.add_child(row)

	return column

## Real placement UI for walls (see wall_placement_selected's own doc
## comment) — deliberately just two cards, not a per-tier list the way
## buildings get one: WallManager.place_wall_line() only ever places fresh
## Wooden segments (upgrade_segment(), reached by selecting an existing
## wall, is still the only way to a Brick/Concrete tier — unchanged from
## before this rework), so a tier picker here would offer choices that
## don't actually exist yet. "Gate" is the same Wooden segment/cost, just
## intrinsically weaker (WallSegment.is_gate's own doc comment) — a
## deliberate weak point the player places on purpose, not a difference
## the build menu needs to price separately.
func _build_wall_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Walls"
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(HUDStyles.build_card(
		"Wooden Wall",
		WallVisuals.tier_texture(WallCatalog.WOODEN),
		"Cost: %s\nClick+drag to draw — auto-splits into ≤100m pieces." % HUDStyles.format_resource_dict(WallCatalog.get_build_cost(WallCatalog.WOODEN)),
		func() -> void: wall_placement_selected.emit(false),
	))
	row.add_child(HUDStyles.build_card(
		"Gate",
		WallVisuals.tier_texture(WallCatalog.WOODEN),
		"Cost: %s\nSame as a Wooden Wall, deliberately weaker." % HUDStyles.format_resource_dict(WallCatalog.get_build_cost(WallCatalog.WOODEN)),
		func() -> void: wall_placement_selected.emit(true),
	))
	column.add_child(row)

	return column

func _build_building_card(definition: BuildingDefinition) -> Control:
	return HUDStyles.build_card(
		definition.display_name,
		BuildingVisuals.building_texture(definition.building_type),
		_describe_building(definition),
		_on_building_button_pressed.bind(definition.building_type),
	)

## "how much each building costs, the upkeep it requires, and what it
## actually does e.g. how much of x does it produce daily, does it produce
## units and if so what kind" (user request) — one compact multi-line
## string covering all three asks per building.
func _describe_building(definition: BuildingDefinition) -> String:
	var lines: Array[String] = []
	lines.append("Cost: %s" % HUDStyles.format_resource_dict(definition.construction_cost))
	var upkeep := HUDStyles.format_resource_dict(definition.daily_upkeep)
	if not upkeep.is_empty():
		lines.append("Upkeep: %s/day" % upkeep)
	lines.append(_describe_effect(definition))
	return "\n".join(lines)

## The "what it actually does" line — production (resource amounts),
## training (and what kind of units), and housing all read directly off the
## same BuildingDefinition fields the rest of the game already simulates
## from, so this can't silently drift out of sync with real behavior. Falls
## back to a plain structural description for the handful of buildings with
## none of the above (Town Hall, Watchtower, Ammo Dump, ...) so a card is
## never left with a blank third line.
func _describe_effect(definition: BuildingDefinition) -> String:
	var parts: Array[String] = []
	for resource_type in definition.daily_output:
		var amount := float(definition.daily_output[resource_type])
		if resource_type == GameEnums.ResourceType.ENERGY:
			parts.append("+%s Energy (one-time)" % String.num(amount, 0))
		else:
			parts.append("+%s %s/day" % [String.num(amount, 0), ResourceVisuals.display_name(resource_type)])
	if definition.population_provided > 0:
		parts.append("Houses %d population" % definition.population_provided)
	if definition.can_train_units:
		parts.append("Trains units: %s" % _trainable_unit_names())
	if not parts.is_empty():
		return "; ".join(parts)
	if not definition.zoc_roles.is_empty():
		return "Extends territorial control"
	if definition.vision_radius > 0:
		return "Extends vision"
	return "Support structure"

## "does it produce units and if so what kind" (user request) — every
## `can_train_units` building trains off the SAME UnitCatalog roster today
## (UnitManager.train_unit() takes no building-specific filter — see
## UnitPanelView's own training-button loop, which iterates
## UnitCatalog.get_all_definitions() the identical way), so this is genuinely
## accurate for Garrison and any future can_train_units building alike, not
## a Garrison-specific guess.
func _trainable_unit_names() -> String:
	var names: Array[String] = []
	for unit_definition in UnitCatalog.get_all_definitions():
		names.append(unit_definition.display_name)
	return ", ".join(names)

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
