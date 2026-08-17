class_name BuildMenuView
extends PanelContainer

## Build menu — the UI for BuildingManager.place_building_at_world(). One
## 60x60 icon per BuildingCatalog definition, grouped into a grid per
## category; clicking one arms placement mode by emitting building_selected.
## This view only knows about *selecting* a type — it has no idea what a hex
## or a world position is; BuildPlacementController is what turns a
## selection into an actual placed building.
##
## All categories visible at once, no tabs — every category is its own
## always-visible column (header + an icon grid) inside one
## horizontally-scrolling strip, per user feedback ("too many clicks having
## to scroll to the right tab, just display all the tabs all the time").
##
## Icon-only, not text cards — per user feedback ("should just show the icon
## of the building, and then when you mouse over each building, it should
## show a tooltip that displays all the information"): each 60x60
## BuildingIconButton carries its full name/cost/upkeep/effect breakdown in
## a hover tooltip (that class's own _make_custom_tooltip()) instead of
## always-visible text, so many more buildings fit the same bottom-bar
## footprint than the old card layout could.
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
## A fifth column (Infrastructure rework, todo.md, 2026-08-16) — arming
## SupplyLinePlacementController's hex-click-chain flow is its own shape
## too, keyed by GameEnums.SupplyLineType rather than a building type.
signal infrastructure_placement_selected(line_type: GameEnums.SupplyLineType)

## DEFENSE_WORKS excluded from this list — folded into
## _build_defense_and_walls_column() instead of getting its own generic
## column, per user feedback ("Defense Works & Walls should be combined
## into one category").
const CATEGORY_ORDER: Array[GameEnums.BuildingCategory] = [
	GameEnums.BuildingCategory.HOUSING_CIVIL,
	GameEnums.BuildingCategory.INDUSTRY_EXTRACTION,
	GameEnums.BuildingCategory.AGRICULTURE,
]

## Fixed row count, unbounded columns — a category grid grows SIDEWAYS as
## more buildings land in it (Industry & Extraction alone has over two
## dozen), using the same horizontal ScrollContainer the whole bar already
## scrolls with, rather than growing taller than MainHUD.BOTTOM_BAR_HEIGHT's
## fixed budget (vertical scrolling is deliberately disabled on that
## container — see _ready()'s own comment). 3 rows, not 2 — "have 3 rows of
## buildings instead of 2" (user feedback) — trades some of each category's
## width for less of it, closer to fitting the whole bar without a
## horizontal scrollbar at typical window widths (not guaranteed at every
## width: 60x60 icons at Industry & Extraction's own 26-building count still
## need 9 columns even at 3 rows).
const _ICON_GRID_ROWS: int = 3
const _ICON_SPACING: float = 4.0  ## Tightened from 6.0 — "reduce the padding and spacing as its taking up too much room" (user feedback).

var _tech_manager: TechManager
var _resource_manager: ResourceManager

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDStyles.style_panel(self)
	_rebuild()

## Optional on both counts, same "unset means a narrower feature just does
## less" convention every other MainHUD-wired view follows: no tech_manager
## means every building shows unlocked (fails open — a missing wire
## shouldn't softlock the whole build menu); no resource_manager means cost
## lines in tooltips never red-highlight (still shown, just not affordability-checked).
func setup(tech_manager: TechManager, resource_manager: ResourceManager) -> void:
	_tech_manager = tech_manager
	_resource_manager = resource_manager
	if _tech_manager:
		_tech_manager.tech_researched.connect(_on_tech_researched)
	if is_inside_tree():
		_rebuild()

func _on_tech_researched(_tech_id: StringName) -> void:
	_rebuild()  ## A newly-researched building_tier tech may have just unlocked one or more icons — cheap enough at this scale (dozens of icons) to just rebuild, same reasoning TacticalHexView._redraw() leans on.

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  ## Sideways scrolling replaces tab-clicking — see class doc.
	add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)  ## Tightened from 16 — see _ICON_SPACING's own comment.
	# With vertical scrolling disabled, ScrollContainer would otherwise
	# stretch `columns` to fill the full bar height and top-align its
	# (shorter, real content) inside that, leaving a visibly empty gap below
	# the icons while MinimapView (SIZE_SHRINK_CENTER) sits vertically
	# centered in the same row. SHRINK_CENTER here makes `columns` request
	# only its own real content height and center within the leftover
	# space, the same vertical anchor the minimap uses — "make sure that it
	# lines up with the mini map" (user feedback).
	columns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(columns)

	for category in CATEGORY_ORDER:
		var definitions := BuildingCatalog.get_definitions_in_category(category)
		if definitions.is_empty():
			continue  # An empty column would just be dead space.
		columns.add_child(_build_category_column(category, definitions))

	columns.add_child(_build_defense_and_walls_column())
	columns.add_child(_build_infrastructure_column())

func _build_category_column(category: GameEnums.BuildingCategory, definitions: Array[BuildingDefinition]) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)  ## Tightened from 6 — see _ICON_SPACING's own comment.

	var header := Label.new()
	header.text = _category_name(category)
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var colors := HUDStyles.category_card_colors(_category_color_key(category))
	column.add_child(_build_icon_grid(definitions, func(definition: BuildingDefinition) -> Control:
		return _build_building_icon(definition, colors)
	))

	return column

## Defense Works (BuildingCatalog's DEFENSE_WORKS category — Search Light,
## the only entry left in it) and Walls (a wholly separate placement flow, WallManager,
## never a BuildingCatalog category at all) merged into ONE column, per
## user feedback ("Defense Works & Walls should be combined into one
## category... red and white") — same shared red/white
## category_card_colors("defense_walls") regardless of which underlying
## system a given card arms. Header shortened to "Defenses & Walls" per
## later user feedback. Wall icons are just two, not a per-tier list:
## WallManager.place_wall_line() only places fresh Wooden segments —
## upgrade_segment(), reached by selecting an existing wall, is the only
## way to a Brick/Concrete tier. "Gate" is the same Wooden segment/cost,
## just intrinsically weaker (WallSegment.is_gate's own doc comment) — a
## deliberate weak point the player places on purpose, not a difference
## this menu needs to price separately. Neither Wall icon is ever
## research-locked here (see class doc's setup() comment on tech_manager
## scope — only BuildingCatalog definitions carry a `tier` this menu checks).
func _build_defense_and_walls_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)  ## Tightened from 6 — see _ICON_SPACING's own comment.

	var header := Label.new()
	header.text = "Defenses & Walls"
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var colors := HUDStyles.category_card_colors("defense_walls")
	var items: Array = []
	items.append_array(BuildingCatalog.get_definitions_in_category(GameEnums.BuildingCategory.DEFENSE_WORKS))
	items.append("wooden_wall")
	items.append("gate")
	column.add_child(_build_icon_grid(items, func(item) -> Control:
		if item is BuildingDefinition:
			return _build_building_icon(item, colors)
		var is_gate: bool = item == "gate"
		return _build_wall_icon(is_gate, colors)
	))

	return column

func _build_wall_icon(is_gate: bool, colors: Dictionary) -> Control:
	var cost_text := HUDStyles.format_resource_dict(WallCatalog.get_build_cost(WallCatalog.WOODEN))
	var tooltip := func() -> String:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % ("Gate" if is_gate else "Wooden Wall"))
		lines.append("Cost: %s" % cost_text)
		lines.append("Gate: same cost, deliberately weaker." if is_gate else "Click+drag to draw — auto-splits into ≤100m pieces.")
		return "\n".join(lines)

	var icon := BuildingIconButton.new()
	icon.setup(
		WallVisuals.tier_texture(WallCatalog.WOODEN), true, colors,
		func() -> void: wall_placement_selected.emit(is_gate),
		tooltip,
	)
	return icon

## Road/Railway/Canal/Bridge — a wholly separate placement flow
## (SupplyLinePlacementController, hex-click-chain) the same way Walls are,
## so this gets its own column rather than folding into
## _build_defense_and_walls_column() (Infrastructure isn't a defensive
## structure). Each icon only ever arms tier 0 — same "fresh placement
## stays base-tier-only, upgrade_segment() is the only way to advance it"
## precedent Walls already established. Icon art comes from
## SupplyLineVisuals.line_texture() (falls back to the category-color box
## with no image if a texture is missing, same contract every other
## *Visuals.gd texture lookup follows). Never research-locked here — same
## reasoning _build_defense_and_walls_column() documents.
func _build_infrastructure_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)  ## Tightened from 6 — see _ICON_SPACING's own comment.

	var header := Label.new()
	header.text = "Infrastructure"
	HUDStyles.style_label(header, true)
	column.add_child(header)

	var colors := HUDStyles.category_card_colors("infrastructure")
	var line_types: Array[GameEnums.SupplyLineType] = [GameEnums.SupplyLineType.ROAD, GameEnums.SupplyLineType.RAILWAY, GameEnums.SupplyLineType.CANAL, GameEnums.SupplyLineType.BRIDGE]
	column.add_child(_build_icon_grid(line_types, func(line_type: GameEnums.SupplyLineType) -> Control:
		return _build_infrastructure_icon(line_type, colors)
	))

	return column

func _build_infrastructure_icon(line_type: GameEnums.SupplyLineType, colors: Dictionary) -> Control:
	var tooltip := func() -> String:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % SupplyLineCatalog.get_display_name(line_type, 0))
		lines.append("Cost: %s/hex" % HUDStyles.format_resource_dict(SupplyLineCatalog.get_build_cost(line_type, 0)))
		lines.append(_describe_infrastructure_bonus(line_type))
		lines.append("Click a hex, then an adjacent hex to connect it.")
		return "\n".join(lines)

	var icon := BuildingIconButton.new()
	icon.setup(SupplyLineVisuals.line_texture(line_type), true, colors, func() -> void: infrastructure_placement_selected.emit(line_type), tooltip)
	return icon

func _describe_infrastructure_bonus(line_type: GameEnums.SupplyLineType) -> String:
	var bonus_percent := int(round((SupplyLineCatalog.get_speed_multiplier(line_type, 0) - 1.0) * 100.0))
	if line_type == GameEnums.SupplyLineType.BRIDGE:
		return "+%d%% Speed — only buildable across water." % bonus_percent
	return "+%d%% Speed, ignores terrain penalty." % bonus_percent

## Distributes `items` round-robin into `_ICON_GRID_ROWS` fixed HBoxContainer
## rows stacked in a VBoxContainer — a FIXED-HEIGHT, unbounded-WIDTH grid
## (see _ICON_GRID_ROWS's own doc comment for why: GridContainer's native
## "fixed columns, wrap downward" shape would blow through
## MainHUD.BOTTOM_BAR_HEIGHT the moment a category holds more than a
## handful of buildings). `build_icon` is a Callable(item) -> Control so
## this one layout helper serves BuildingDefinition icons, wall icons, and
## infrastructure icons alike.
func _build_icon_grid(items: Array, build_icon: Callable) -> Control:
	var rows: Array[HBoxContainer] = []
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", _ICON_SPACING)
	for row_index in range(_ICON_GRID_ROWS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _ICON_SPACING)
		rows.append(row)
		grid.add_child(row)

	for i in range(items.size()):
		rows[i % _ICON_GRID_ROWS].add_child(build_icon.call(items[i]))

	return grid

func _build_building_icon(definition: BuildingDefinition, colors: Dictionary) -> Control:
	var unlocked := not _tech_manager or _tech_manager.is_building_tier_unlocked(definition.tier)
	var icon := BuildingIconButton.new()
	icon.setup(
		BuildingVisuals.building_texture(definition.building_type), unlocked, colors,
		_on_building_button_pressed.bind(definition.building_type),
		func() -> String: return _describe_building_tooltip(definition, unlocked),
	)
	return icon

## Covers cost (red-highlighted per-resource where unaffordable — "highlight
## in red which resources the user cannot afford to spend", user feedback),
## upkeep, effect (production/training/housing), and unlock state in one
## BBCode block for BuildingIconButton's tooltip.
func _describe_building_tooltip(definition: BuildingDefinition, unlocked: bool) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % definition.display_name)
	lines.append("Cost: %s" % _format_cost_bbcode(definition.construction_cost))
	# ENERGY/POPULATION entries are one-time capacity draws
	# (CapacityAllocator), not a recurring "/day" cost — excluded here the
	# same way _describe_effect()/_add_capacity_stats() (UnitPanelView) keep
	# them out of their own "/day" lines.
	var recurring_upkeep: Dictionary = {}
	for resource_type in definition.daily_upkeep:
		if not CapacityAllocator.CAPACITY_RESOURCE_TYPES.has(resource_type):
			recurring_upkeep[resource_type] = definition.daily_upkeep[resource_type]
	var upkeep := HUDStyles.format_resource_dict(recurring_upkeep)
	if not upkeep.is_empty():
		lines.append("Upkeep: %s/day" % upkeep)
	lines.append(_describe_effect(definition))
	if not unlocked:
		lines.append("[color=#%s]Not yet researched[/color]" % HUDStyles.DANGER_COLOR.to_html(false))
	return "\n".join(lines)

## Same shape as HUDStyles.format_resource_dict() but wraps any resource the
## player currently can't afford in [color=...] — needs _resource_manager
## (optional; without it, every cost renders in the plain, un-highlighted
## style HUDStyles.format_resource_dict() already produces).
func _format_cost_bbcode(costs: Dictionary) -> String:
	if not _resource_manager:
		return HUDStyles.format_resource_dict(costs)
	var parts: Array[String] = []
	for resource_type in costs:
		var amount := float(costs[resource_type])
		var text := "%s %s" % [String.num(amount, 1).rstrip("0").rstrip("."), ResourceVisuals.display_name(resource_type)]
		if _resource_manager.get_amount(resource_type) < amount:
			text = "[color=#%s]%s[/color]" % [HUDStyles.DANGER_COLOR.to_html(false), text]
		parts.append(text)
	return ", ".join(parts)

## The "what it actually does" line — production/training/housing all read
## directly off the same BuildingDefinition fields the rest of the game
## simulates from, so this can't drift out of sync with real behavior.
## Falls back to a plain structural description for buildings with none of
## the above (Town Hall, Watchtower, Ammo Dump, ...) so a tooltip is never
## left without a "what does this do" line.
func _describe_effect(definition: BuildingDefinition) -> String:
	var parts: Array[String] = []
	for resource_type in definition.daily_output:
		# POPULATION is skipped here — it's the CapacityAllocator
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
## building is selected (UnitPanelView's own training grid) — this tooltip
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
