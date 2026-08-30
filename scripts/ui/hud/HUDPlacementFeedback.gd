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
	# design_doc.md §2.1's "Going dark". building_restart_rejected is the
	# reason this cluster is wired at all rather than left to the building
	# panel: BuildingPowerController cancels a restart at COMPLETION if the
	# grid can no longer carry it, days after the player ordered it and quite
	# possibly with a different building selected, so it has nowhere else to
	# be seen.
	building_manager.building_powered_down.connect(_on_building_powered_down)
	building_manager.building_powered_up.connect(_on_building_powered_up)
	building_manager.building_restart_started.connect(_on_building_restart_started)
	building_manager.building_restart_cancelled.connect(_on_building_restart_cancelled)
	building_manager.building_restart_rejected.connect(_on_building_action_rejected)
	building_manager.power_down_rejected.connect(_on_building_action_rejected)

func wire_wall_manager(wall_manager: WallManager) -> void:
	wall_manager.repair_started.connect(_on_wall_repair_started)
	wall_manager.placement_rejected.connect(_on_wall_placement_rejected)

func wire_build_placement_controller(controller: BuildPlacementController) -> void:
	controller.placement_started.connect(_on_placement_started)
	controller.placement_ended.connect(_on_placement_ended)
	controller.placement_blocked.connect(_on_placement_blocked)

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

## Same router as every other rejection — a click refused before
## BuildingManager was consulted has to read identically to one refused by it,
## since the player made the same gesture and got the same nothing.
func _on_placement_blocked(reason: String) -> void:
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

## Names all four things going dark actually stops, because none of them are
## visible anywhere on screen — noise and light are a NoiseManager field the
## player never sees directly, and it is the whole reason for pulling the
## switch (design_doc.md §2.1, vision.md P2).
func _on_building_powered_down(instance: BuildingInstance) -> void:
	_toast.show("%s switched off — no production, no upkeep, no noise, no light." % _building_name(instance))

func _on_building_powered_up(instance: BuildingInstance) -> void:
	_toast.show("%s is back online." % _building_name(instance))

func _on_building_restart_started(instance: BuildingInstance, days: int) -> void:
	_toast.show("Restarting %s — online in %d day%s." % [_building_name(instance), days, "" if days == 1 else "s"])

## Distinct from _on_building_powered_down(): nothing changed about what the
## building emits (it was already dark), only that it is no longer coming back.
func _on_building_restart_cancelled(instance: BuildingInstance) -> void:
	_toast.show("%s's restart cancelled — it stays dark." % _building_name(instance))

## Same router every other rejection uses — see _on_placement_blocked().
func _on_building_action_rejected(_instance: BuildingInstance, reason: String) -> void:
	_toast.show(reason)

func _building_name(instance: BuildingInstance) -> String:
	return instance.definition.display_name if instance and instance.definition else "Building"
