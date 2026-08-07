class_name UnitPanelView
extends ScrollContainer

## Selection-driven HUD panel — the training-and-orders counterpart to
## BuildMenuView, reading UnitCommandController's current selection instead
## of arming a placement mode. Three states:
##   - Nothing selected: an idle hint.
##   - A Military-ZoC building selected: one Train button per UnitCatalog
##     definition (tier-locked/unaffordable ones shown disabled with
##     UnitManager.get_training_error()'s reason as a tooltip — same
##     "queryable rejection reason" convention BuildMenuView's cost tooltip
##     and BuildPlacementController's ghost color both already lean on).
##   - A unit selected: its stats (HP, rank, current order) plus Hold /
##     Garrison / Patrol (click-to-record waypoints on the map, Confirm
##     here) / Retrain buttons, all wired straight back into
##     UnitCommandController — this view never calls UnitManager/
##     UnitOrderController directly, same "dumb display, controller owns
##     the actual call" split BuildMenuView keeps with BuildPlacementController.

var _unit_command_controller: UnitCommandController
var _unit_manager: UnitManager

var _list: VBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(260, 220)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)
	_render_idle()

func setup(unit_command_controller: UnitCommandController, unit_manager: UnitManager) -> void:
	_unit_command_controller = unit_command_controller
	_unit_manager = unit_manager
	if _unit_command_controller:
		_unit_command_controller.unit_selected.connect(_on_unit_selected)
		_unit_command_controller.building_selected.connect(_on_building_selected)
		_unit_command_controller.selection_cleared.connect(_on_selection_cleared)
		_unit_command_controller.patrol_recording_changed.connect(_on_patrol_recording_changed)
	if _unit_manager:
		_unit_manager.unit_trained.connect(_on_roster_changed)
		_unit_manager.unit_removed.connect(_on_roster_changed)
		_unit_manager.unit_retrained.connect(_on_roster_changed)

func _on_unit_selected(instance: UnitInstance) -> void:
	_render_unit_panel(instance)

func _on_building_selected(coord: Vector2i) -> void:
	_render_training_panel(coord)

func _on_selection_cleared() -> void:
	_render_idle()

## Re-renders whatever's currently selected so the panel stays live —
## covers both the patrol-waypoint counter changing while recording and a
## training/roster change (a unit dying, a fresh one trained) invalidating
## the buttons already drawn.
func _on_patrol_recording_changed(_is_recording: bool, _waypoint_count: int) -> void:
	_refresh_current_selection()

func _on_roster_changed(_instance: UnitInstance) -> void:
	_refresh_current_selection()

func _refresh_current_selection() -> void:
	if not _unit_command_controller:
		return
	var instance := _unit_command_controller.get_selected_unit()
	if instance:
		_render_unit_panel(instance)

func _clear_list() -> void:
	for child in _list.get_children():
		child.queue_free()

func _render_idle() -> void:
	_clear_list()
	var hint := Label.new()
	hint.text = "Click a unit to command it, or a Garrison to train one."
	_list.add_child(hint)

func _render_training_panel(coord: Vector2i) -> void:
	_clear_list()
	var header := Label.new()
	header.text = "Train at %s" % coord
	_list.add_child(header)
	if not _unit_manager:
		return
	for definition in UnitCatalog.get_all_definitions():
		var button := Button.new()
		button.text = "%s (T%d %s)" % [definition.display_name, definition.tier, _role_name(definition.role)]
		var error := _unit_manager.get_training_error(definition.unit_type, coord)
		button.disabled = not error.is_empty()
		button.tooltip_text = error if not error.is_empty() else _format_cost(definition.training_cost)
		button.pressed.connect(_on_train_pressed.bind(coord, definition.unit_type))
		_list.add_child(button)

func _on_train_pressed(coord: Vector2i, unit_type: GameEnums.UnitType) -> void:
	if _unit_command_controller:
		_unit_command_controller.train_at_selected_building(coord, unit_type)

func _render_unit_panel(instance: UnitInstance) -> void:
	_clear_list()
	var definition := instance.definition

	var header := Label.new()
	header.text = "%s (T%d %s)" % [definition.display_name, definition.tier, _role_name(definition.role)]
	_list.add_child(header)

	var stats := Label.new()
	stats.text = "HP %d/%d — %s — %s" % [int(instance.current_hp), int(definition.max_hp), _rank_name(UnitMorale.get_rank(instance)), _order_name(instance.order)]
	_list.add_child(stats)

	var hold_button := Button.new()
	hold_button.text = "Hold"
	hold_button.pressed.connect(_unit_command_controller.order_hold)
	_list.add_child(hold_button)

	var garrison_button := Button.new()
	garrison_button.text = "Garrison"
	garrison_button.pressed.connect(_unit_command_controller.order_garrison)
	_list.add_child(garrison_button)

	if _unit_command_controller.is_recording_patrol():
		var recording_label := Label.new()
		recording_label.text = "Recording patrol — %d waypoint(s). Left-click the map to add, right-click/Esc to cancel." % _unit_command_controller.get_patrol_waypoint_count()
		_list.add_child(recording_label)
		var confirm_button := Button.new()
		confirm_button.text = "Confirm Patrol"
		confirm_button.disabled = _unit_command_controller.get_patrol_waypoint_count() == 0
		confirm_button.pressed.connect(_unit_command_controller.confirm_patrol_recording)
		_list.add_child(confirm_button)
	else:
		var patrol_button := Button.new()
		patrol_button.text = "Patrol… (click waypoints on map)"
		patrol_button.pressed.connect(_unit_command_controller.begin_patrol_recording)
		_list.add_child(patrol_button)

	var retrain_header := Label.new()
	retrain_header.text = "Retrain into:"
	_list.add_child(retrain_header)
	var any_retrain_candidate := false
	for candidate in UnitCatalog.get_all_definitions():
		if candidate.role != definition.role or candidate.tier <= definition.tier:
			continue
		any_retrain_candidate = true
		var retrain_button := Button.new()
		retrain_button.text = candidate.display_name
		var error := _unit_manager.get_retrain_error(instance, candidate.unit_type) if _unit_manager else "No UnitManager wired."
		retrain_button.disabled = not error.is_empty()
		retrain_button.tooltip_text = error if not error.is_empty() else _format_cost(_retrain_preview_cost(candidate))
		retrain_button.pressed.connect(_on_retrain_pressed.bind(candidate.unit_type))
		_list.add_child(retrain_button)
	if not any_retrain_candidate:
		var none_label := Label.new()
		none_label.text = "(top tier for this role)"
		_list.add_child(none_label)

func _on_retrain_pressed(unit_type: GameEnums.UnitType) -> void:
	if _unit_command_controller:
		_unit_command_controller.retrain_selected(unit_type)

func _retrain_preview_cost(definition: UnitDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in definition.training_cost:
		cost[resource_type] = float(definition.training_cost[resource_type]) * UnitManager.RETRAIN_COST_FRACTION
	return cost

func _format_cost(cost: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in cost:
		if not first:
			text += ", "
		text += "%d %s" % [int(cost[resource_type]), ResourceVisuals.display_name(resource_type)]
		first = false
	return text

func _role_name(role: GameEnums.UnitRole) -> String:
	match role:
		GameEnums.UnitRole.MELEE:
			return "Melee"
		GameEnums.UnitRole.RANGED:
			return "Ranged"
		GameEnums.UnitRole.SPECIAL:
			return "Special"
		_:
			return "?"

func _rank_name(rank: UnitMorale.Rank) -> String:
	match rank:
		UnitMorale.Rank.ELITE:
			return "Elite"
		UnitMorale.Rank.VETERAN:
			return "Veteran"
		_:
			return "Rookie"

func _order_name(order: GameEnums.UnitOrderType) -> String:
	match order:
		GameEnums.UnitOrderType.MOVE:
			return "Moving"
		GameEnums.UnitOrderType.ATTACK_MOVE:
			return "Attack-Moving"
		GameEnums.UnitOrderType.PATROL:
			return "Patrolling"
		GameEnums.UnitOrderType.GARRISON:
			return "Garrisoned"
		_:
			return "Holding"
