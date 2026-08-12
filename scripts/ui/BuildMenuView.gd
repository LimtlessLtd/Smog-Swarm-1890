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

## DEFENSE_WORKS deliberately excluded from this list — user request,
## playtest round 5: "Defense Works & Walls should be combined into one
## category" — it's folded into the dedicated `_build_defense_and_walls_column()`
## below instead of getting its own generic column.
const CATEGORY_ORDER: Array[GameEnums.BuildingCategory] = [
	GameEnums.BuildingCategory.HOUSING_CIVIL,
	GameEnums.BuildingCategory.INDUSTRY_EXTRACTION,
	GameEnums.BuildingCategory.AGRICULTURE,
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

## An earlier pass (playtest round 6: "reduce the size of the building
## cards... reduce the size of the text... its currently very large")
## shrunk these from HUDStyles.build_card()'s own defaults (132/44, tuned
## for UnitPanelView's roomier top-left panel, unaffected by this change
## since it doesn't pass these explicitly) down to 92/28/11/9 — but that
## went far enough that a card's autowrapped icon+name+details column
## regularly exceeded MainHUD.BOTTOM_BAR_HEIGHT's own (also-shrunk) 130px,
## clipping text off the bottom of the screen (next playtest round's own
## report: "make each building card... large enough so the text fits...
## some of them currently go off the bottom of the screen"). Settled on a
## middle ground here — noticeably more compact than the original
## 132/44/15/13, but wide/tall enough that a typical multi-clause details
## string ("+3 Bricks/day; Houses 6 population; Trains: Melee, Ranged")
## wraps to 2-3 lines instead of 4-5. MainHUD.BOTTOM_BAR_HEIGHT (see that
## file's own doc comment) was raised to match — verified together via an
## actual live screenshot, not just this arithmetic, since autowrap line
## count is a real-font-metrics question static reasoning can't settle on
## its own (same lesson the minimap-hiding regression a few rounds back
## already taught this project once).
const _CARD_WIDTH: float = 128.0  ## Widened again alongside MainHUD.BOTTOM_BAR_HEIGHT — see that constant's own doc comment for the live-testing history that found 112 still wrapped Garrison's 2-resource cost line ("90 Bricks, 25 Cast Iron") across 2 lines by itself.
const _CARD_ICON_SIZE: float = 32.0
const _CARD_NAME_FONT_SIZE: int = 12
const _CARD_DETAILS_FONT_SIZE: int = 10

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
	# User request (playtest round 6: "make sure that it lines up with the
	# mini map") — with vertical scrolling disabled, ScrollContainer would
	# otherwise stretch `columns` to fill the FULL bar height and then
	# top-align its (now much shorter, since the round-6 card shrink) real
	# content inside that — leaving a visibly empty gap below the cards
	# while MinimapView (SIZE_SHRINK_CENTER, MainHUD's own
	# _build_bottom_bar()) sits vertically centered in the same row.
	# SHRINK_CENTER here makes `columns` request only its own real content
	# height and center within the leftover space instead, the same
	# vertical anchor the minimap already uses.
	columns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(columns)

	for category in CATEGORY_ORDER:
		var definitions := _visible_definitions(category)
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

## Defense Works (BuildingCatalog's DEFENSE_WORKS category — Searchlight
## Tower today) and Walls (a wholly separate placement flow, WallManager,
## never a BuildingCatalog category at all) merged into ONE column (user
## request, playtest round 5: "Defense Works & Walls should be combined
## into one category... red and white") — same shared red/white
## `category_card_colors("defense_walls")` regardless of which of the two
## underlying systems a given card actually arms. Wall cards are
## deliberately just two, not a per-tier list — see the wall_placement_selected
## signal's own doc comment for why (WallManager.place_wall_line() only
## ever places fresh Wooden segments; upgrade_segment(), reached by
## selecting an existing wall, is still the only way to a Brick/Concrete
## tier). "Gate" is the same Wooden segment/cost, just intrinsically weaker
## (WallSegment.is_gate's own doc comment) — a deliberate weak point the
## player places on purpose, not a difference the build menu needs to
## price separately.
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
	for definition in _visible_definitions(GameEnums.BuildingCategory.DEFENSE_WORKS):
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
		parts.append("Trains: %s" % _trainable_unit_roles())
	if not parts.is_empty():
		return "; ".join(parts)
	if not definition.zoc_roles.is_empty():
		return "Extends territorial control"
	if definition.vision_radius > 0:
		return "Extends vision"
	return "Support structure"

## "does it produce units and if so what kind" (user request) — a compact
## ROLE summary (Melee/Ranged/Special), not every individual unit's own
## display name. **Real bug fix (playtest round 5: "the mini map no longer
## appears anywhere"):** the original version joined ALL ~18
## `UnitCatalog.get_all_definitions()` display names into one line — for
## Garrison specifically (today's only `can_train_units` building) that
## single wrapped Label came out ~580px tall (confirmed via a live debug
## print), which forced the WHOLE bottom bar — build menu AND the minimap
## sharing the same row — far past its intended `BOTTOM_BAR_HEIGHT`,
## silently squeezing the minimap out of any renderable space (a Control's
## `size` can never go below its own computed minimum). The full roster is
## still genuinely visible, per-unit, with real art/cost/upkeep, the moment
## a `can_train_units` building is actually selected (`UnitPanelView`'s own
## training grid) — this card only needs to answer "what KIND", which a
## short role list does without the runaway height. Every `can_train_units`
## building trains off the SAME UnitCatalog roster today (UnitManager.
## train_unit() takes no building-specific filter — see UnitPanelView's own
## training-button loop, which iterates get_all_definitions() the identical
## way), so this is genuinely accurate for Garrison and any future
## can_train_units building alike, not a Garrison-specific guess.
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

func _visible_definitions(category: GameEnums.BuildingCategory) -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for definition in BuildingCatalog.get_definitions_in_category(category):
		if not _EXCLUDED_FROM_MENU.has(definition.building_type):
			result.append(definition)
	return result

func _on_building_button_pressed(building_type: GameEnums.BuildingType) -> void:
	building_selected.emit(building_type)

## Maps to the string keys HUDStyles.category_card_colors() actually
## understands — kept as its own small function (not folded into
## _category_name()) since the two mappings could diverge in principle
## (a future category might want a display name but reuse another
## category's color scheme) even though today they're 1:1.
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
