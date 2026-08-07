class_name BuildMenuView
extends ScrollContainer

## Build menu (design doc Phase 6.1 — "the actual UI for
## BuildingManager.place_building_at_world(), built in Phase 2.5, never
## called by anything since"). One button per BuildingCatalog definition,
## grouped by category; pressing one arms placement mode by emitting
## building_selected. This view only knows about *selecting* a type — it has
## no idea what a hex or a world position is; BuildPlacementController
## (Phase 6.1, `/scripts/world`) is what turns a selection into an actual
## placed building.

signal building_selected(building_type: GameEnums.BuildingType)

const CATEGORY_ORDER: Array[GameEnums.BuildingCategory] = [
	GameEnums.BuildingCategory.HOUSING_CIVIL,
	GameEnums.BuildingCategory.INDUSTRY_EXTRACTION,
	GameEnums.BuildingCategory.AGRICULTURE,
]

func _ready() -> void:
	custom_minimum_size = Vector2(260, 260)
	HUDStyles.style_panel(self)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list)
	_populate(list)

func _populate(list: VBoxContainer) -> void:
	for category in CATEGORY_ORDER:
		var header := Label.new()
		header.text = _category_name(category)
		HUDStyles.style_label(header, true)
		list.add_child(header)
		for definition in BuildingCatalog.get_definitions_in_category(category):
			var button := Button.new()
			button.text = definition.display_name
			# Full cost as a hover tooltip rather than inline text — cost
			# strings ("Church Steeple Watchtower: 100 Bricks, 10 Cast
			# Iron") run too long to fit the panel alongside the name.
			button.tooltip_text = _format_cost(definition.construction_cost)
			button.pressed.connect(_on_building_button_pressed.bind(definition.building_type))
			HUDStyles.style_button(button)
			list.add_child(button)

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
