class_name UnitPanelView
extends ScrollContainer

## Selection-driven HUD panel — the training-and-orders counterpart to
## BuildMenuView, reading UnitCommandController's current selection instead
## of arming a placement mode. Five states:
##   - Nothing selected: an idle hint.
##   - A building that can train units (Garrison today) selected: one Train
##     button per UnitCatalog definition (tier-locked/unaffordable ones
##     shown disabled with UnitManager.get_training_error()'s reason as a
##     tooltip — same "queryable rejection reason" convention BuildMenuView's
##     cost tooltip and BuildPlacementController's ghost color both already
##     lean on), PLUS a Repair section if the building is ruined.
##   - Any OTHER building selected (Town Hall, Foundry, a damaged
##     Workhouse, ...): just its name/HP/state and — real bug fixed, player
##     report ("Same goes for all the buildings" re: no way to select/repair
##     one) — a Repair button once it's actually ruined. Every building is
##     now selectable, not just training ones (UnitCommandController's own
##     doc comment has the full story).
##   - A wall segment selected (also a first — walls had no selection path
##     at all before): tier/HP/breached state and the same kind of Repair
##     button.
##   - A unit selected: its stats (HP, rank, current order) plus Hold /
##     Garrison / Patrol (click-to-record waypoints on the map, Confirm
##     here) / Retrain buttons, all wired straight back into
##     UnitCommandController — this view never calls UnitManager/
##     UnitOrderController/BuildingManager/WallManager directly, same "dumb
##     display, controller owns the actual call" split BuildMenuView keeps
##     with BuildPlacementController. `_building_manager`/`_wall_manager`
##     below are the one exception, and only ever used to LISTEN for live
##     state changes (repair completing, HP changing) — same read-only
##     pattern `_unit_manager`'s own roster-change listeners already use,
##     never to issue a command themselves.

var _unit_command_controller: UnitCommandController
var _unit_manager: UnitManager
var _building_manager: BuildingManager
var _wall_manager: WallManager

var _list: VBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(260, 220)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## No dialog should ever need a horizontal scrollbar — see TechTreeView's own note on this.
	HUDStyles.style_panel(self)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)
	_render_idle()

func setup(unit_command_controller: UnitCommandController, unit_manager: UnitManager, building_manager: BuildingManager = null, wall_manager: WallManager = null) -> void:
	_unit_command_controller = unit_command_controller
	_unit_manager = unit_manager
	_building_manager = building_manager
	_wall_manager = wall_manager
	if _unit_command_controller:
		_unit_command_controller.unit_selected.connect(_on_unit_selected)
		_unit_command_controller.building_instance_selected.connect(_on_building_selected)
		_unit_command_controller.wall_segment_selected.connect(_on_wall_selected)
		_unit_command_controller.selection_cleared.connect(_on_selection_cleared)
		_unit_command_controller.patrol_recording_changed.connect(_on_patrol_recording_changed)
	if _unit_manager:
		_unit_manager.unit_trained.connect(_on_roster_changed)
		_unit_manager.unit_removed.connect(_on_roster_changed)
		_unit_manager.unit_retrained.connect(_on_roster_changed)
	if _building_manager:
		_building_manager.repair_started.connect(_on_building_repair_changed)
		_building_manager.building_repaired.connect(_on_building_repair_changed)
		_building_manager.building_ruined.connect(_on_building_repair_changed)
	if _wall_manager:
		_wall_manager.repair_started.connect(_on_wall_repair_changed)
		_wall_manager.wall_segment_repaired.connect(_on_wall_repair_changed)
		_wall_manager.wall_segment_breached.connect(_on_wall_repair_changed)

func _on_unit_selected(instance: UnitInstance) -> void:
	_render_unit_panel(instance)

func _on_building_selected(instance: BuildingInstance) -> void:
	_render_building_panel(instance)

func _on_wall_selected(segment: WallSegment) -> void:
	_render_wall_panel(segment)

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

## A repair starting/finishing (or a fresh ruin) should immediately update
## the Repair button's enabled state/label rather than leaving a stale
## "Repair" button clickable on a building that's already mid-repair —
## same live-refresh reasoning _on_roster_changed already covers for units.
func _on_building_repair_changed(instance: BuildingInstance, _extra: Variant = null) -> void:
	if _unit_command_controller and _unit_command_controller.get_selected_building() == instance:
		_refresh_current_selection()

func _on_wall_repair_changed(segment: WallSegment, _extra: Variant = null) -> void:
	if _unit_command_controller and _unit_command_controller.get_selected_wall() == segment:
		_refresh_current_selection()

func _refresh_current_selection() -> void:
	if not _unit_command_controller:
		return
	var unit := _unit_command_controller.get_selected_unit()
	if unit:
		_render_unit_panel(unit)
		return
	var building := _unit_command_controller.get_selected_building()
	if building:
		_render_building_panel(building)
		return
	var wall := _unit_command_controller.get_selected_wall()
	if wall:
		_render_wall_panel(wall)

func _clear_list() -> void:
	for child in _list.get_children():
		child.queue_free()

func _render_idle() -> void:
	_clear_list()
	var hint := Label.new()
	hint.text = "Click a unit to command it, a building to inspect/repair it, or a wall segment to repair it."
	HUDStyles.style_label(hint)
	_list.add_child(hint)

## Training panel (a `can_train_units` building, Garrison today) and the
## general building-info panel (everything else) share one function —
## both need the same header/repair section, and a training building can
## itself be ruined and need repair same as any other, so branching inside
## one panel avoids duplicating that shared section across two.
func _render_building_panel(instance: BuildingInstance) -> void:
	_clear_list()
	var definition := instance.definition
	var header := Label.new()
	header.text = "%s%s" % [definition.display_name, " (RUINED)" if instance.is_ruined else ""]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	if not instance.is_ruined:
		var stats := Label.new()
		stats.text = "HP %d/%d" % [int(instance.current_hp), int(definition.get_max_hp())]
		HUDStyles.style_label(stats)
		_list.add_child(stats)

	_add_repair_button(
		instance.is_ruined,
		func() -> String: return _unit_command_controller.get_selected_building_repair_error(),
		_unit_command_controller.repair_selected_building
	)

	if definition.can_train_units:
		var coord := instance.hex_coord
		var train_header := Label.new()
		train_header.text = "Train at %s" % coord
		HUDStyles.style_label(train_header, true)
		_list.add_child(train_header)
		if _unit_manager:
			for unit_definition in UnitCatalog.get_all_definitions():
				var button := Button.new()
				button.text = "%s (T%d %s)" % [unit_definition.display_name, unit_definition.tier, _role_name(unit_definition.role)]
				var error := _unit_manager.get_training_error(unit_definition.unit_type, coord)
				button.disabled = not error.is_empty()
				button.tooltip_text = error if not error.is_empty() else _format_cost(unit_definition.training_cost)
				button.pressed.connect(_on_train_pressed.bind(coord, unit_definition.unit_type))
				HUDStyles.style_button(button)
				_list.add_child(button)

func _render_wall_panel(segment: WallSegment) -> void:
	_clear_list()
	var header := Label.new()
	header.text = "Wall segment%s%s" % [" (Gate)" if segment.is_gate else "", " (BREACHED)" if segment.is_breached() else ""]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	var tier_name := WallCatalog.get_display_name(segment.tier)
	var stats := Label.new()
	stats.text = "%s — HP %d/%d" % [tier_name, int(segment.current_hp), int(segment.get_max_hp())]
	HUDStyles.style_label(stats)
	_list.add_child(stats)

	_add_repair_button(
		segment.is_breached(),
		func() -> String: return _unit_command_controller.get_selected_wall_repair_error(),
		_unit_command_controller.repair_selected_wall
	)

## Shared by both panels above — a Repair button only even APPEARS once the
## thing is actually damaged enough to repair (`is_ruined`/`is_breached()`,
## matching BuildingManager.get_repair_error()/WallManager.get_repair_error()'s
## own first check each), disabled with the real rejection reason as a
## tooltip otherwise (same queryable-rejection convention as every other
## action button in this view).
func _add_repair_button(is_damaged: bool, error_getter: Callable, repair_action: Callable) -> void:
	if not is_damaged or not _unit_command_controller:
		return
	var button := Button.new()
	button.text = "Repair"
	var error: String = error_getter.call()
	button.disabled = not error.is_empty()
	button.tooltip_text = error if not error.is_empty() else "Repair this."
	button.pressed.connect(func() -> void: repair_action.call())
	HUDStyles.style_button(button)
	_list.add_child(button)

func _on_train_pressed(coord: Vector2i, unit_type: GameEnums.UnitType) -> void:
	if _unit_command_controller:
		_unit_command_controller.train_at_selected_building(coord, unit_type)

func _render_unit_panel(instance: UnitInstance) -> void:
	_clear_list()
	var definition := instance.definition

	var header := Label.new()
	header.text = "%s (T%d %s)" % [definition.display_name, definition.tier, _role_name(definition.role)]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	var stats := Label.new()
	stats.text = "HP %d/%d — %s — %s" % [int(instance.current_hp), int(definition.max_hp), _rank_name(UnitMorale.get_rank(instance)), _order_name(instance.order)]
	HUDStyles.style_label(stats)
	_list.add_child(stats)

	var hold_button := Button.new()
	hold_button.text = "Hold"
	hold_button.pressed.connect(_unit_command_controller.order_hold)
	HUDStyles.style_button(hold_button)
	_list.add_child(hold_button)

	var garrison_button := Button.new()
	garrison_button.text = "Garrison"
	garrison_button.pressed.connect(_unit_command_controller.order_garrison)
	HUDStyles.style_button(garrison_button)
	_list.add_child(garrison_button)

	if _unit_command_controller.is_recording_patrol():
		var recording_label := Label.new()
		recording_label.text = "Recording patrol — %d waypoint(s). Left-click the map to add, right-click/Esc to cancel." % _unit_command_controller.get_patrol_waypoint_count()
		HUDStyles.style_label(recording_label)
		_list.add_child(recording_label)
		var confirm_button := Button.new()
		confirm_button.text = "Confirm Patrol"
		confirm_button.disabled = _unit_command_controller.get_patrol_waypoint_count() == 0
		confirm_button.pressed.connect(_unit_command_controller.confirm_patrol_recording)
		HUDStyles.style_button(confirm_button)
		_list.add_child(confirm_button)
	else:
		var patrol_button := Button.new()
		patrol_button.text = "Patrol… (click waypoints on map)"
		patrol_button.pressed.connect(_unit_command_controller.begin_patrol_recording)
		HUDStyles.style_button(patrol_button)
		_list.add_child(patrol_button)

	var retrain_header := Label.new()
	retrain_header.text = "Retrain into:"
	HUDStyles.style_label(retrain_header, true)
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
		HUDStyles.style_button(retrain_button)
		_list.add_child(retrain_button)
	if not any_retrain_candidate:
		var none_label := Label.new()
		none_label.text = "(top tier for this role)"
		HUDStyles.style_label(none_label)
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
