class_name HUDPlacementFeedback
extends RefCounted

## Building/wall placement mode text + construction/repair/rejection toasts —
## the largest single cluster of MainHUD's toast/mode-label wiring, extracted
## so BuildingManager/WallManager/BuildPlacementController/
## WallPlacementController's combined dependency lives in one place instead
## of spread across MainHUD's own handler list.

var _mode_label: Label
var _toast: HUDToastRouter

func _init(mode_label: Label, toast: HUDToastRouter) -> void:
	_mode_label = mode_label
	_toast = toast

func wire_building_manager(building_manager: BuildingManager) -> void:
	building_manager.placement_rejected.connect(_on_placement_rejected)
	building_manager.construction_started.connect(_on_construction_started)
	building_manager.repair_started.connect(_on_building_repair_started)

func wire_wall_manager(wall_manager: WallManager) -> void:
	wall_manager.repair_started.connect(_on_wall_repair_started)
	wall_manager.placement_rejected.connect(_on_wall_placement_rejected)

func wire_build_placement_controller(controller: BuildPlacementController) -> void:
	controller.placement_started.connect(_on_placement_started)
	controller.placement_ended.connect(_on_placement_ended)

## placement_ended is reused directly for walls too — it only ever clears
## _mode_label and doesn't care what was being placed.
func wire_wall_placement_controller(controller: WallPlacementController) -> void:
	controller.placement_started.connect(_on_wall_placement_started)
	controller.placement_ended.connect(_on_placement_ended)

func wire_logistics_network(logistics_network: LogisticsNetwork) -> void:
	logistics_network.placement_rejected.connect(_on_infrastructure_placement_rejected)

## placement_ended reused again, same reasoning as wire_wall_placement_controller()'s own comment.
func wire_supply_line_placement_controller(controller: SupplyLinePlacementController) -> void:
	controller.placement_started.connect(_on_infrastructure_placement_started)
	controller.placement_ended.connect(_on_placement_ended)

func _on_placement_started(building_type: GameEnums.BuildingType) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var display_name := definition.display_name if definition else "building"
	_mode_label.text = "Placing: %s — click the map (Shift-click for more, Right-click/Esc to cancel)" % display_name

func _on_placement_ended() -> void:
	_mode_label.text = ""

func _on_placement_rejected(_building_type: GameEnums.BuildingType, _coord: Vector2i, reason: String) -> void:
	_toast.show(reason)

func _on_wall_placement_started(_tier: int) -> void:
	_mode_label.text = "Placing wall — click and drag along the map (Shift-drag for more, Right-click/Esc to cancel)"

func _on_wall_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, reason: String) -> void:
	_toast.show(reason)

func _on_infrastructure_placement_started(line_type: GameEnums.SupplyLineType, tier: int) -> void:
	_mode_label.text = "Placing %s — click a hex, then an adjacent hex to connect it (Right-click/Esc to cancel)" % SupplyLineCatalog.get_display_name(line_type, tier)

func _on_infrastructure_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, reason: String) -> void:
	_toast.show(reason)

func _on_construction_started(building_type: GameEnums.BuildingType, _coord: Vector2i, days: int) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var display_name := definition.display_name if definition else "Building"
	_toast.show("%s under construction — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_building_repair_started(instance: BuildingInstance, days: int) -> void:
	var display_name := instance.definition.display_name if instance and instance.definition else "Building"
	_toast.show("Repairing %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_wall_repair_started(_segment: WallSegment, days: int) -> void:
	_toast.show("Repairing wall segment — ready in %d day%s." % [days, "" if days == 1 else "s"])
