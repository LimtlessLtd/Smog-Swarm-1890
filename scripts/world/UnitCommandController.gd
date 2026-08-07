class_name UnitCommandController
extends Node2D

## Turns clicks on the map into unit selection and RTS order issuing (design
## doc Phase 5.6's "standard RTS order set") — the same missing link
## BuildPlacementController fills for buildings: UnitManager.train_unit()
## and UnitOrderController.issue_*_order() have existed since Phase 5.4/5.6,
## but nothing in the input/HUD layer has ever called them
## (UnitOrderController's own doc comment: "no UI calls these yet — Phase
## 6+"). This is that Phase 6 piece.
##
## Left-click selects whatever's on a hex: a friendly unit first (mirrors
## the design doc's "click a unit to command it" RTS convention), else a
## building projecting Military Zone of Control (in practice a Garrison —
## see UnitManager's own doc comment) so it can be trained at. Right-click
## issues a Move order to the currently selected unit — standard RTS
## shorthand, and the natural counterpart to left-click-to-select. Escape
## deselects (and cancels an in-progress patrol recording first, same
## "cancel the more specific mode first" precedent BuildPlacementController
## already sets for Shift-click chaining vs. a plain click).
##
## UnitPanelView (Phase 6.1's HUD) is the only thing that reads this
## controller's selection/patrol-recording state and calls its order
## methods — this class never touches a Control node itself, same "world
## input layer stays UI-agnostic" split BuildPlacementController/MainHUD
## already keep.
##
## Parented as a HexGridMap/StrategicOverlayManager/BuildPlacementController
## sibling under WorldRoot for the same reason BuildPlacementController is:
## shares the same coordinate space (including whatever transform
## CameraController applies for the isometric perspective toggle), so
## hex-from-click math doesn't need to special-case either view mode.

signal unit_selected(instance: UnitInstance)
signal building_selected(coord: Vector2i)
signal selection_cleared
signal patrol_recording_changed(is_recording: bool, waypoint_count: int)

const _SELECTION_RING_RADIUS := 16.0
const _SELECTION_RING_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const _PATROL_PREVIEW_COLOR := Color(0.9, 0.85, 0.2, 0.9)

@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var building_manager_path: NodePath
@export var build_placement_controller_path: NodePath  ## Optional — while build placement mode is active, this controller yields input to it entirely rather than fighting over the same click (one input mode at a time).

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _unit_order_controller: UnitOrderController
var _building_manager: BuildingManager
var _build_placement_controller: BuildPlacementController

var _selected_unit: UnitInstance
var _is_recording_patrol: bool = false
var _patrol_waypoints: Array[Vector2i] = []

var _selection_ring: Line2D
var _patrol_preview: Line2D

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_removed.connect(_on_unit_removed)
	if unit_order_controller_path != NodePath():
		_unit_order_controller = get_node(unit_order_controller_path)
		_unit_order_controller.unit_moved.connect(_on_unit_moved)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if build_placement_controller_path != NodePath():
		_build_placement_controller = get_node(build_placement_controller_path)

	_selection_ring = Line2D.new()
	_selection_ring.closed = true
	_selection_ring.width = 3.0
	_selection_ring.default_color = _SELECTION_RING_COLOR
	_selection_ring.points = _ring_points(_SELECTION_RING_RADIUS)
	_selection_ring.visible = false
	add_child(_selection_ring)

	_patrol_preview = Line2D.new()
	_patrol_preview.width = 4.0
	_patrol_preview.default_color = _PATROL_PREVIEW_COLOR
	add_child(_patrol_preview)

func get_selected_unit() -> UnitInstance:
	return _selected_unit

func is_recording_patrol() -> bool:
	return _is_recording_patrol

func get_patrol_waypoint_count() -> int:
	return _patrol_waypoints.size()

func _unhandled_input(event: InputEvent) -> void:
	if _build_placement_controller and _build_placement_controller.is_placing():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _is_recording_patrol:
			_cancel_patrol_recording()
		else:
			clear_selection()

func _on_left_click(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	if _is_recording_patrol:
		_patrol_waypoints.append(coord)
		_update_patrol_preview()
		patrol_recording_changed.emit(true, _patrol_waypoints.size())
		return
	_select_at(coord)

func _on_right_click(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	if _is_recording_patrol:
		_cancel_patrol_recording()
		return
	if _selected_unit and _unit_order_controller:
		_unit_order_controller.issue_move_order(_selected_unit, coord)

func _select_at(coord: Vector2i) -> void:
	if _unit_manager:
		var units := _unit_manager.get_units_at(coord)
		if not units.is_empty():
			_selected_unit = units[0]
			_selection_ring.position = HexCoord.axial_to_world(coord)
			_selection_ring.visible = true
			unit_selected.emit(_selected_unit)
			return
	if _building_manager and _has_military_zoc_building(coord):
		_selected_unit = null
		_selection_ring.visible = false
		building_selected.emit(coord)
		return
	clear_selection()

func _has_military_zoc_building(coord: Vector2i) -> bool:
	for instance in _building_manager.get_buildings_at(coord):
		if instance.definition.zoc_roles.has(GameEnums.ZoneOfControlType.MILITARY):
			return true
	return false

func clear_selection() -> void:
	_selected_unit = null
	_selection_ring.visible = false
	selection_cleared.emit()

## --- Order commands, called by UnitPanelView's buttons ---------------------

func order_hold() -> void:
	if _selected_unit and _unit_order_controller:
		_unit_order_controller.issue_hold_order(_selected_unit)

func order_garrison() -> void:
	if _selected_unit and _unit_order_controller:
		_unit_order_controller.issue_garrison_order(_selected_unit)

func begin_patrol_recording() -> void:
	if not _selected_unit:
		return
	_is_recording_patrol = true
	_patrol_waypoints.clear()
	_update_patrol_preview()
	patrol_recording_changed.emit(true, 0)

func confirm_patrol_recording() -> void:
	if _selected_unit and _unit_order_controller and not _patrol_waypoints.is_empty():
		_unit_order_controller.issue_patrol_order(_selected_unit, _patrol_waypoints)
	_cancel_patrol_recording()

func _cancel_patrol_recording() -> void:
	_is_recording_patrol = false
	_patrol_waypoints.clear()
	_update_patrol_preview()
	patrol_recording_changed.emit(false, 0)

func _update_patrol_preview() -> void:
	var points := PackedVector2Array()
	for coord in _patrol_waypoints:
		points.append(HexCoord.axial_to_world(coord))
	_patrol_preview.points = points

func retrain_selected(new_type: GameEnums.UnitType) -> void:
	if _selected_unit and _unit_manager:
		_unit_manager.retrain_unit(_selected_unit, new_type)

func train_at_selected_building(coord: Vector2i, unit_type: GameEnums.UnitType) -> void:
	if _unit_manager:
		_unit_manager.train_unit(unit_type, coord)

func _on_unit_removed(instance: UnitInstance) -> void:
	if _selected_unit == instance:
		clear_selection()

func _on_unit_moved(instance: UnitInstance, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	if instance == _selected_unit:
		_selection_ring.position = HexCoord.axial_to_world(to_coord)

func _ring_points(radius: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(radius * cos(angle), radius * sin(angle)))
	return points
