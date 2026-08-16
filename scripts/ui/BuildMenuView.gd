class_name BuildMenuView
extends PanelContainer

## Build menu — the UI for BuildingManager.place_building_at_world(). One
## card per BuildingCatalog definition, grouped into a column per category;
## clicking one arms placement mode by emitting building_selected. This
## view only knows about *selecting* a type — it has no idea what a hex or
## a world position is; BuildPlacementController is what turns a selection
## into an actual placed building.
##
## All categories visible at once, no tabs — every category is its own
## always-visible column (header + a row of building cards) inside one
## horizontally-scrolling strip, per user feedback ("too many clicks having
## to scroll to the right tab, just display all the tabs all the time").
##
## Cards, not bare-text buttons — per user feedback ("display the pictures
## of the building... how much each building costs, the upkeep it
## requires, and what it actually does"), each card shows the building's
## real art (BuildingVisuals.building_texture(), same texture
## TacticalHexView renders), its name, and a compact cost/upkeep/effect
## summary, all visible without hovering.
##
## Merged into one bottom bar with the minimap — this view doesn't position
## or size itself (MainHUD._build_bottom_bar() does, sizing it to
## SIZE_EXPAND_FILL alongside a fixed-width MinimapView in the same row);
## extends PanelContainer so HUDStyles.style_panel() actually draws a
## background (only Panel/PanelContainer draw a "panel" theme stylebox — a
## plain Control silently ignores one).

signal building_selected(building_type: GameEnums.BuildingType)
## A fourth column, own signal rather than reusing building_selected —
## arming WallPlacementController's click-DRAG flow is a different shape
## from BuildPlacementController's click-to-place one, not a building type.
signal wall_placement_selected(is_gate: bool)

## DEFENSE_WORKS excluded from this list — folded into
## _build_defense_and_walls_column() instead of getting its own generic
## column, per user feedback ("Defense Works & Walls should be combined
## into one category").
const CATEGORY_ORDER: Array[GameEnums.BuildingCategory] = [
	GameEnums.BuildingCategory.HOUSING_CIVIL,
	GameEnums.BuildingCategory.INDUSTRY_EXTRACTION,
	GameEnums.BuildingCategory.AGRICULTURE,
]

## Card size settled after two rounds of user feedback: an early pass
## shrunk cards down to 92/28/11/9 ("reduce the size of the building
## cards... its currently very large"), which then clipped multi-clause
## details text off the bottom of the screen ("make each building card...
## large enough so the text fits"). This is the middle ground — wide/tall
## enough that a typical details string ("+3 Bricks/day; Houses 6
## population; Trains: Melee, Ranged") wraps to 2-3 lines instead of 4-5.
## MainHUD.BOTTOM_BAR_HEIGHT was raised to match, verified together via a
## live screenshot (autowrap line count is a real-font-metrics question,
## not something static reasoning settles on its own).
const _CARD_WIDTH: float = 128.0
const _CARD_ICON_SIZE: float = 32.0
const _CARD_NAME_FONT_SIZE: int = 12
const _CARD_DETAILS_FONT_SIZE: int = 10

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDStyles.style_panel(self)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  ## Sideways scrolling replaces tab-clicking — see class doc.
	add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	# With vertical scrolling disabled, ScrollContainer would otherwise
	# stretch `columns` to fill the full bar height and top-align its
	# (shorter, post-shrink) real content inside that, leaving a visibly
	# empty gap below the cards while MinimapView (SIZE_SHRINK_CENTER)
	# sits vertically centered in the same row. SHRINK_CENTER here makes
	# `columns` request only its own real content height and center within
	# the leftover space, the same vertical anchor the minimap uses —
	# "make sure that it lines up with the mini map" (user feedback).
	columns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(columns)

	for category in CATEGORY_ORDER:
		var definitions := BuildingCatalog.get_definitions_in_category(category)
		if definitions.is_empty():
			continue  # An empty column would just be dead space.
		columns.add_child(_build_category_column(category, definitions))

	columns.add_child(_build_defense_and_walls_column())

func _build_category_column(category: GameEnums.BuildingCategory, definitions: Array[BuildingDefinition]) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = _category_name(category)
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var colors := HUDStyles.category_card_colors(_category_color_key(category))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for definition in definitions:
		row.add_child(_build_building_card(definition, colors))
	column.add_child(row)

	return column

## Defense Works (BuildingCatalog's DEFENSE_WORKS category — Search Light,
## the only entry left in it) and Walls (a wholly separate placement flow, WallManager,
## never a BuildingCatalog category at all) merged into ONE column, per
## user feedback ("Defense Works & Walls should be combined into one
## category... red and white") — same shared red/white
## category_card_colors("defense_walls") regardless of which underlying
## system a given card arms. Wall cards are just two, not a per-tier list:
## WallManager.place_wall_line() only places fresh Wooden segments —
## upgrade_segment(), reached by selecting an existing wall, is the only
## way to a Brick/Concrete tier. "Gate" is the same Wooden segment/cost,
## just intrinsically weaker (WallSegment.is_gate's own doc comment) — a
## deliberate weak point the player places on purpose, not a difference
## this menu needs to price separately.
func _build_defense_and_walls_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Defense Works & Walls"
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var colors := HUDStyles.category_card_colors("defense_walls")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for definition in BuildingCatalog.get_definitions_in_category(GameEnums.BuildingCategory.DEFENSE_WORKS):
		row.add_child(_build_building_card(definition, colors))
	row.add_child(HUDStyles.build_card(
		"Wooden Wall",
		WallVisuals.tier_texture(WallCatalog.WOODEN),
		"Cost: %s\nClick+drag to draw — auto-splits into ≤100m pieces." % HUDStyles.format_resource_dict(WallCatalog.get_build_cost(WallCatalog.WOODEN)),
		func() -> void: wall_placement_selected.emit(false),
		true, _CARD_WIDTH, _CARD_ICON_SIZE, colors, _CARD_NAME_FONT_SIZE, _CARD_DETAILS_FONT_SIZE,
	))
	row.add_child(HUDStyles.build_card(
		"Gate",
		WallVisuals.tier_texture(WallCatalog.WOODEN),
		"Cost: %s\nSame as a Wooden Wall, deliberately weaker." % HUDStyles.format_resource_dict(WallCatalog.get_build_cost(WallCatalog.WOODEN)),
		func() -> void: wall_placement_selected.emit(true),
		true, _CARD_WIDTH, _CARD_ICON_SIZE, colors, _CARD_NAME_FONT_SIZE, _CARD_DETAILS_FONT_SIZE,
	))
	column.add_child(row)

	return column

func _build_building_card(definition: BuildingDefinition, colors: Dictionary = {}) -> Control:
	return HUDStyles.build_card(
		definition.display_name,
		BuildingVisuals.building_texture(definition.building_type),
		_describe_building(definition),
		_on_building_button_pressed.bind(definition.building_type),
		true, _CARD_WIDTH, _CARD_ICON_SIZE, colors, _CARD_NAME_FONT_SIZE, _CARD_DETAILS_FONT_SIZE,
	)

## Covers cost, upkeep, and effect (production/training/housing) per user
## feedback ("how much each building costs, the upkeep it requires, and
## what it actually does e.g. how much of x does it produce daily, does it
## produce units and if so what kind") in one compact multi-line string.
func _describe_building(definition: BuildingDefinition) -> String:
	var lines: Array[String] = []
	lines.append("Cost: %s" % HUDStyles.format_resource_dict(definition.construction_cost))
	# ENERGY/POPULATION entries are one-time capacity draws
	# (BuildingCapacityAllocator), not a recurring "/day" cost — excluded
	# here the same way _describe_effect()/_add_capacity_stats() (UnitPanelView)
	# keep them out of their own "/day" lines.
	var recurring_upkeep: Dictionary = {}
	for resource_type in definition.daily_upkeep:
		if not BuildingCapacityAllocator.CAPACITY_RESOURCE_TYPES.has(resource_type):
			recurring_upkeep[resource_type] = definition.daily_upkeep[resource_type]
	var upkeep := HUDStyles.format_resource_dict(recurring_upkeep)
	if not upkeep.is_empty():
		lines.append("Upkeep: %s/day" % upkeep)
	lines.append(_describe_effect(definition))
	return "\n".join(lines)

## The "what it actually does" line — production/training/housing all read
## directly off the same BuildingDefinition fields the rest of the game
## simulates from, so this can't drift out of sync with real behavior.
## Falls back to a plain structural description for buildings with none of
## the above (Town Hall, Watchtower, Ammo Dump, ...) so a card is never
## left with a blank third line.
func _describe_effect(definition: BuildingDefinition) -> String:
	var parts: Array[String] = []
	for resource_type in definition.daily_output:
		# POPULATION is skipped here — it's the BuildingCapacityAllocator
		# capacity grant mirroring population_provided (BuildingCatalog's
		# housing builders), already covered by "Houses %d population" below;
		# listing it again here would double it up under a misleading "/day" label.
		if resource_type == GameEnums.ResourceType.POPULATION:
			continue
		var amount := float(definition.daily_output[resource_type])
		if resource_type == GameEnums.ResourceType.ENERGY:
			parts.append("+%s Energy (one-time)" % String.num(amount, 0))
		else:
			parts.append("+%s %s/day" % [String.num(amount, 0), ResourceVisuals.display_name(resource_type)])
	if definition.population_provided > 0:
		parts.append("Houses %d population" % definition.population_provided)
	if definition.can_train_units:
		parts.append("Trains: %s" % _trainable_unit_roles())
	if not parts.is_empty():
		return "; ".join(parts)
	if not definition.zoc_roles.is_empty():
		return "Extends territorial control"
	if definition.vision_radius > 0:
		return "Extends vision"
	return "Support structure"

## A compact ROLE summary (Melee/Ranged/Special), not every individual
## unit's own display name — joining all ~18 UnitCatalog.get_all_definitions()
## display names into one line for Garrison used to render a ~580px-tall
## wrapped Label, forcing the whole bottom bar (build menu AND minimap
## sharing the same row) past its intended BOTTOM_BAR_HEIGHT and squeezing
## the minimap out of any renderable space (a Control's size can never go
## below its own computed minimum). The full roster is still visible,
## per-unit, with real art/cost/upkeep, the moment a can_train_units
## building is selected (UnitPanelView's own training grid) — this card
## only needs to answer "what KIND". Every can_train_units building trains
## off the SAME UnitCatalog roster today (UnitManager.train_unit() takes no
## building-specific filter), so this is accurate for Garrison and any
## future can_train_units building alike.
func _trainable_unit_roles() -> String:
	var role_names: Array[String] = []
	for unit_definition in UnitCatalog.get_all_definitions():
		var role_name := _role_display_name(unit_definition.role)
		if not role_names.has(role_name):
			role_names.append(role_name)
	return ", ".join(role_names)

func _role_display_name(role: GameEnums.UnitRole) -> String:
	match role:
		GameEnums.UnitRole.MELEE:
			return "Melee"
		GameEnums.UnitRole.RANGED:
			return "Ranged"
		GameEnums.UnitRole.SPECIAL:
			return "Special"
		_:
			return "?"

func _on_building_button_pressed(building_type: GameEnums.BuildingType) -> void:
	building_selected.emit(building_type)

## Maps to the string keys HUDStyles.category_card_colors() understands —
## kept separate from _category_name() since the two mappings could
## diverge in principle (a future category might want a display name but
## reuse another category's color scheme) even though today they're 1:1.
func _category_color_key(category: GameEnums.BuildingCategory) -> String:
	match category:
		GameEnums.BuildingCategory.HOUSING_CIVIL:
			return "housing_civil"
		GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
			return "industry_extraction"
		GameEnums.BuildingCategory.AGRICULTURE:
			return "agriculture"
		_:
			return ""

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
