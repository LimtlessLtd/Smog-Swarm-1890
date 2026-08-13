class_name UnitCommandController
extends Node2D

## Turns clicks on the map into unit selection and RTS order issuing — the
## same missing link BuildPlacementController fills for buildings:
## UnitManager.train_unit() and UnitOrderController.issue_*_order() have no
## caller anywhere else in the input/HUD layer.
##
## Left-click selects whatever's on a hex: a friendly unit first, else the
## nearest wall segment if the click landed close to one, else the nearest
## building on that hex (any type, not just training ones). Right-click
## issues a Move order to the currently selected unit. Escape deselects
## (and cancels an in-progress patrol recording first, same "cancel the more
## specific mode first" precedent BuildPlacementController sets for
## Shift-click chaining vs. a plain click).
##
## ANY building on the clicked hex is selectable (picked by proximity to the
## exact click position when several share a hex via local_position, same
## disambiguation TacticalHexView._resolved_building_position() solves for
## rendering), and a click within _WALL_CLICK_TOLERANCE world units of a
## wall segment's own line (hex_a center to hex_b center) selects that
## segment instead. UnitPanelView reads get_selected_building()/
## get_selected_wall() to show a Repair button.
##
## UnitPanelView is the only thing that reads this controller's selection/
## patrol-recording state and calls its order methods — this class never
## touches a Control node itself, same "world input layer stays UI-agnostic"
## split BuildPlacementController/MainHUD keep.
##
## Parented as a HexGridMap/StrategicOverlayManager/BuildPlacementController
## sibling under WorldRoot: shares the same coordinate space (including
## CameraController's isometric transform), so hex-from-click math doesn't
## need to special-case either view mode.

signal unit_selected(instance: UnitInstance)
signal building_instance_selected(instance: BuildingInstance)
signal wall_segment_selected(segment: WallSegment)
signal selection_cleared
signal patrol_recording_changed(is_recording: bool, waypoint_count: int)

const _SELECTION_RING_RADIUS := 16.0
const _SELECTION_RING_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const _PATROL_PREVIEW_COLOR := Color(0.9, 0.85, 0.2, 0.9)
const _WALL_HIGHLIGHT_COLOR := Color(1.0, 0.9, 0.2, 0.9)  ## Same gold as _SELECTION_RING_COLOR — one shared "this is selected" language regardless of what kind of thing it is.
const _WALL_CLICK_TOLERANCE := 24.0  ## Max distance (world units) from a wall segment's own line (hex_a center to hex_b center) a click still counts as "on" it. Small relative to HexCoord.HEX_SIZE (512).
const _UNIT_CLICK_TOLERANCE := 40.0  ## Max distance (world units) from a unit's own real rendered position a click still counts as "on" it. Covers a whole squad's visual scatter cluster (TacticalEntityLayer.FIGURE_SPREAD, 20.0, plus jitter).

@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var building_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var build_placement_controller_path: NodePath  ## Optional — while build placement mode is active, this controller yields input to it entirely.
@export var wall_placement_controller_path: NodePath  ## Optional — same yield-input reasoning, for WallPlacementController's own click-drag mode.

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _unit_order_controller: UnitOrderController
var _building_manager: BuildingManager
var _wall_manager: WallManager
var _build_placement_controller: BuildPlacementController
var _wall_placement_controller: WallPlacementController

var _selected_unit: UnitInstance
var _selected_building: BuildingInstance
var _selected_wall: WallSegment
var _is_recording_patrol: bool = false
var _patrol_waypoints: Array[Vector2i] = []
var _patrol_waypoint_locals: Array[Vector2] = []  ## Index-aligned with _patrol_waypoints — see UnitInstance.patrol_waypoint_locals' own doc comment.

var _selection_ring: Line2D
var _wall_highlight: Line2D
var _patrol_preview: Line2D

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_removed.connect(_on_unit_removed)
	if unit_order_controller_path != NodePath():
		_unit_order_controller = get_node(unit_order_controller_path)
		_unit_order_controller.unit_order_issued.connect(_on_unit_order_issued)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_removed.connect(_on_building_removed)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.wall_segment_removed.connect(_on_wall_segment_removed)
	if build_placement_controller_path != NodePath():
		_build_placement_controller = get_node(build_placement_controller_path)
	if wall_placement_controller_path != NodePath():
		_wall_placement_controller = get_node(wall_placement_controller_path)

	_selection_ring = Line2D.new()
	_selection_ring.closed = true
	_selection_ring.width = 3.0
	_selection_ring.default_color = _SELECTION_RING_COLOR
	_selection_ring.points = _ring_points(_SELECTION_RING_RADIUS)
	_selection_ring.visible = false
	add_child(_selection_ring)

	# Two-point line rather than a ring — a wall segment IS a line (its own
	# point_a to point_b), so its selection highlight traces that shape
	# instead of reusing the unit/building ring, which would misleadingly
	# imply a single point rather than a whole span.
	_wall_highlight = Line2D.new()
	_wall_highlight.width = 10.0
	_wall_highlight.default_color = _WALL_HIGHLIGHT_COLOR
	_wall_highlight.visible = false
	add_child(_wall_highlight)

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
	if _wall_placement_controller and _wall_placement_controller.is_placing():
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
		_patrol_waypoint_locals.append(world_pos - HexCoord.axial_to_world(coord))
		_update_patrol_preview()
		patrol_recording_changed.emit(true, _patrol_waypoints.size())
		return
	_select_at(coord, world_pos)

## A selected unit moves to the exact clicked point (world_pos minus the
## hex's own center), not just whichever hex it resolves to — see
## UnitInstance.move_target_local's own doc comment for how this reaches
## the movement math untouched for every hex the path merely passes through.
func _on_right_click(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	if _is_recording_patrol:
		_cancel_patrol_recording()
		return
	if _selected_unit and _unit_order_controller:
		var local_offset := world_pos - HexCoord.axial_to_world(coord)
		_unit_order_controller.issue_move_order(_selected_unit, coord, local_offset)

func _select_at(coord: Vector2i, world_pos: Vector2) -> void:
	if _unit_manager:
		var unit := _closest_unit_within_tolerance(world_pos)
		if unit:
			_select_unit(unit)
			return
	if _wall_manager:
		var wall := _closest_wall_within_tolerance(world_pos)
		if wall:
			_select_wall(wall)
			return
	if _building_manager:
		var buildings := _building_manager.get_buildings_at(coord)
		if not buildings.is_empty():
			var building := _closest_building_within_bounds(buildings, world_pos)
			if building:
				_select_building(building)
				return
	clear_selection()

func _select_unit(instance: UnitInstance) -> void:
	_selected_unit = instance
	_selected_building = null
	_selected_wall = null
	# Reset back to the unit-scoped radius in case the previous selection
	# was a (much bigger) building — see _select_building()'s own comment on
	# why that one uses a different radius from this shared ring.
	_selection_ring.points = _ring_points(_SELECTION_RING_RADIUS)
	# The ring uses the unit's own real, continuously-moving position, not
	# its hex center — same "use the real world position, not a hex-bucket
	# proxy" fix _closest_unit_within_tolerance() applies to hit-testing.
	_selection_ring.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	_selection_ring.visible = true
	_wall_highlight.visible = false
	unit_selected.emit(_selected_unit)

func _select_building(instance: BuildingInstance) -> void:
	_selected_unit = null
	_selected_building = instance
	_selected_wall = null
	# TacticalHexView.BUILDING_SELECTION_RING_RADIUS is derived from
	# BUILDING_HALF_SIZE, so this ring stays sized to the building's box
	# (rather than the unit-scoped _SELECTION_RING_RADIUS, which would
	# render inside the box) automatically if that box size ever changes.
	_selection_ring.points = _ring_points(TacticalHexView.BUILDING_SELECTION_RING_RADIUS)
	_selection_ring.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	_selection_ring.visible = true
	_wall_highlight.visible = false
	building_instance_selected.emit(instance)

func _select_wall(segment: WallSegment) -> void:
	_selected_unit = null
	_selected_building = null
	_selected_wall = segment
	_selection_ring.visible = false
	_wall_highlight.points = PackedVector2Array([segment.point_a, segment.point_b])
	_wall_highlight.visible = true
	wall_segment_selected.emit(segment)

## Closest of possibly-several buildings sharing one hex (real sub-hex
## local_position, e.g. the starting Town Hall + Cast Iron Foundry) to
## where the player actually clicked — same disambiguation
## TacticalHexView._resolved_building_position() solves for rendering,
## applied here to picking. Buildings render as a real
## TacticalHexView.BUILDING_HALF_SIZE-sided box, so a click whose offset
## from a building's own origin exceeds that box on either axis is outside
## its sprite and doesn't count. Returns null when nothing on the hex was
## actually clicked, matching wall selection's own "null means try the next
## candidate, then clear_selection()" contract.
func _closest_building_within_bounds(buildings: Array[BuildingInstance], world_pos: Vector2) -> BuildingInstance:
	var closest: BuildingInstance = null
	var closest_dist: float = INF
	for instance in buildings:
		var origin := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		var offset := world_pos - origin
		if absf(offset.x) > TacticalHexView.BUILDING_HALF_SIZE or absf(offset.y) > TacticalHexView.BUILDING_HALF_SIZE:
			continue
		var dist: float = offset.length_squared()
		if dist < closest_dist:
			closest = instance
			closest_dist = dist
	return closest

## Nearest wall segment whose own line (hex_a center to hex_b center, the
## same geometry it renders as) the click landed within
## _WALL_CLICK_TOLERANCE of — null if nothing is close enough. A flat scan
## over every segment rather than a spatial index: wall counts are small
## (individually-placed defensive chokepoints, not a per-tile grid).
func _closest_wall_within_tolerance(world_pos: Vector2) -> WallSegment:
	var closest: WallSegment = null
	var closest_dist: float = _WALL_CLICK_TOLERANCE
	for segment in _wall_manager.get_segments():
		var dist: float = _distance_to_segment(world_pos, segment.point_a, segment.point_b)
		if dist <= closest_dist:
			closest = segment
			closest_dist = dist
	return closest

## Matches against each unit's own REAL world position
## (HexCoord.axial_to_world(hex_coord) + local_position, exactly what
## TacticalEntityLayer renders it at) within a flat click tolerance, not a
## hex-bucket lookup. hex_coord stays a unit's SOURCE hex for its entire
## crossing under continuous movement and only flips to the destination hex
## once it finishes arriving (MovementStepper.advance_toward_hex()'s own
## doc comment), while world_to_coord() rounds a click to whichever hex
## center is nearer — which flips at the crossing's MIDPOINT, well before
## the unit "arrives" there. A hex-bucket match against get_units_at(coord)
## would silently miss the unit for the entire second half of any crossing.
func _closest_unit_within_tolerance(world_pos: Vector2) -> UnitInstance:
	var closest: UnitInstance = null
	var closest_dist: float = _UNIT_CLICK_TOLERANCE * _UNIT_CLICK_TOLERANCE
	for instance in _unit_manager.get_all_units():
		var origin := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		var dist: float = world_pos.distance_squared_to(origin)
		if dist <= closest_dist:
			closest = instance
			closest_dist = dist
	return closest

## Standard point-to-line-segment distance (clamped projection) — plain
## geometry, no physics engine needed for a handful of line checks.
func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func get_selected_building() -> BuildingInstance:
	return _selected_building

func get_selected_wall() -> WallSegment:
	return _selected_wall

## Thin query wrappers so UnitPanelView (which never calls BuildingManager/
## WallManager directly) can gate and label its own Repair button without a
## manager reference of its own.
func get_selected_building_repair_error() -> String:
	if _selected_building and _building_manager:
		return _building_manager.get_repair_error(_selected_building)
	return "Nothing selected."

func get_selected_wall_repair_error() -> String:
	if _selected_wall and _wall_manager:
		return _wall_manager.get_repair_error(_selected_wall)
	return "Nothing selected."

func repair_selected_building() -> bool:
	if _selected_building and _building_manager:
		return _building_manager.repair_building(_selected_building)
	return false

func repair_selected_wall() -> bool:
	if _selected_wall and _wall_manager:
		return _wall_manager.repair_segment(_selected_wall)
	return false

func get_selected_building_demolish_error() -> String:
	if _selected_building and _building_manager:
		return _building_manager.get_demolish_error(_selected_building)
	return "Nothing selected."

func demolish_selected_building() -> bool:
	if _selected_building and _building_manager:
		return _building_manager.demolish_building(_selected_building)
	return false

func get_selected_wall_demolish_error() -> String:
	if _selected_wall and _wall_manager:
		return _wall_manager.get_demolish_error(_selected_wall)
	return "Nothing selected."

func demolish_selected_wall() -> bool:
	if _selected_wall and _wall_manager:
		return _wall_manager.demolish_segment(_selected_wall)
	return false

func clear_selection() -> void:
	_selected_unit = null
	_selected_building = null
	_selected_wall = null
	_selection_ring.visible = false
	_wall_highlight.visible = false
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
	_patrol_waypoint_locals.clear()
	_update_patrol_preview()
	patrol_recording_changed.emit(true, 0)

func confirm_patrol_recording() -> void:
	if _selected_unit and _unit_order_controller and not _patrol_waypoints.is_empty():
		_unit_order_controller.issue_patrol_order(_selected_unit, _patrol_waypoints, _patrol_waypoint_locals)
	_cancel_patrol_recording()

func _cancel_patrol_recording() -> void:
	_is_recording_patrol = false
	_patrol_waypoints.clear()
	_patrol_waypoint_locals.clear()
	_update_patrol_preview()
	patrol_recording_changed.emit(false, 0)

## Draws through the exact clicked points, not each waypoint's own hex
## center — the preview line, and the eventual patrol route it becomes, are
## drawn from identical positions.
func _update_patrol_preview() -> void:
	var points := PackedVector2Array()
	for i in range(_patrol_waypoints.size()):
		points.append(HexCoord.axial_to_world(_patrol_waypoints[i]) + _patrol_waypoint_locals[i])
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

## Buildings don't disappear on ruin (BuildingInstance.is_ruined, still
## selectable so its Repair button reaches it) — only a genuine removal
## invalidates the instance out from under a stale selection.
func _on_building_removed(instance: BuildingInstance) -> void:
	if _selected_building == instance:
		clear_selection()

func _on_wall_segment_removed(segment: WallSegment) -> void:
	if _selected_wall == segment:
		clear_selection()

## A plain per-frame _process() read of the unit's own real, continuously-
## updated hex_coord + local_position (the exact position TacticalEntityLayer
## renders the unit at) — not a discrete update on UnitOrderController.unit_moved,
## which only fires once per whole hex boundary crossed. Between crossings
## (most of any given move, under continuous movement), the ring needs to
## track the unit's real position, not sit frozen at its last hex.
func _process(_delta: float) -> void:
	if _selected_unit:
		_selection_ring.position = HexCoord.axial_to_world(_selected_unit.hex_coord) + _selected_unit.local_position

## UnitPanelView has no direct reference to UnitOrderController (this
## controller owns that), so an order change reaches it by re-emitting the
## SAME unit_selected signal a fresh selection uses — UnitPanelView
## re-renders identically either way. Only for the currently selected unit.
func _on_unit_order_issued(instance: UnitInstance, _order: GameEnums.UnitOrderType) -> void:
	if instance == _selected_unit:
		unit_selected.emit(instance)

func _ring_points(radius: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(radius * cos(angle), radius * sin(angle)))
	return points
