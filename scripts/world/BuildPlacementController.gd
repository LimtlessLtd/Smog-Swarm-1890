class_name BuildPlacementController
extends Node2D

## Turns a build-menu selection (Phase 6.1's BuildMenuView) into an actual
## placed building — the missing link the design doc calls out:
## BuildingManager.place_building_at_world() has existed since Phase 2.5 but
## nothing has ever called it. Owns the "currently arming a building type"
## state and a small hex-outline ghost preview; BuildMenuView/MainHUD know
## nothing about hexes or world positions, they just tell this "the player
## wants to place a Coal Pithead" via begin_placement().
##
## Parented as a HexGridMap/StrategicOverlayManager sibling under WorldRoot
## (same reasoning as StrategicOverlayManager: shares the same coordinate
## space, including whatever rotation/scale CameraController applies for the
## isometric perspective toggle) so the ghost stays aligned with the grid in
## both perspectives without this class needing to know about that trick.
## Added last among WorldRoot's children in Main.tscn so the ghost draws on
## top of buildings/fog/markers by plain sibling order.
##
## Accessibility (design doc: "every color-coded state paired with a
## distinct shape/icon, never color alone"): the ghost is green/red for
## placeable/blocked, but ALSO a different shape (small hexagon vs. diamond)
## so the distinction doesn't rely on color perception alone.

signal placement_started(building_type: GameEnums.BuildingType)
signal placement_ended

const _VALID_COLOR := Color(0.20, 0.75, 0.30, 0.85)
const _BLOCKED_COLOR := Color(0.80, 0.20, 0.15, 0.85)
const _INDICATOR_RADIUS := 10.0

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager

var _is_placing: bool = false
var _pending_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT

var _ghost_outline: Line2D
var _ghost_indicator: Polygon2D  ## Small hexagon (valid) or diamond (blocked) — the shape half of the color pairing.

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)

	_ghost_outline = Line2D.new()
	_ghost_outline.width = 3.0
	_ghost_outline.closed = true
	_ghost_outline.points = HexCoord.corner_points(Vector2.ZERO)
	add_child(_ghost_outline)

	_ghost_indicator = Polygon2D.new()
	add_child(_ghost_indicator)

	_set_ghost_visible(false)

func is_placing() -> bool:
	return _is_placing

func begin_placement(building_type: GameEnums.BuildingType) -> void:
	_is_placing = true
	_pending_type = building_type
	_set_ghost_visible(true)
	placement_started.emit(building_type)

func cancel_placement() -> void:
	if not _is_placing:
		return
	_is_placing = false
	_set_ghost_visible(false)
	placement_ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return
	if event is InputEventMouseMotion:
		_update_ghost(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_attempt_placement(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()

## Public so a headless self-test can drive placement directly without
## fighting Godot's input-event simulation pipeline — this is the exact same
## call the real mouse-click path above makes.
func _attempt_placement(world_pos: Vector2) -> void:
	if not _building_manager:
		return
	var instance := _building_manager.place_building_at_world(_pending_type, world_pos)
	if not instance:
		return  # BuildingManager already emitted placement_rejected with the reason.
	# Shift-click stays in placement mode for rapid multi-placement of the
	# same building type; a plain click places one and exits placement mode.
	if Input.is_key_pressed(KEY_SHIFT):
		_update_ghost(world_pos)
	else:
		cancel_placement()

func _update_ghost(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	position = HexCoord.axial_to_world(coord)
	var can_place := _building_manager != null and _building_manager.can_place_building(_pending_type, coord)
	var color: Color = _VALID_COLOR if can_place else _BLOCKED_COLOR
	_ghost_outline.default_color = color
	_ghost_indicator.color = color
	_ghost_indicator.polygon = _hexagon_points(_INDICATOR_RADIUS) if can_place else _diamond_points(_INDICATOR_RADIUS)

func _set_ghost_visible(is_visible: bool) -> void:
	_ghost_outline.visible = is_visible
	_ghost_indicator.visible = is_visible
	if is_visible:
		_update_ghost(get_global_mouse_position())

func _hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(radius * cos(angle), radius * sin(angle)))
	return points

func _diamond_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
