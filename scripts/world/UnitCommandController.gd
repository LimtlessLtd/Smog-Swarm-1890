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
## A drag-box or select_units() picked several at once. unit_selected still fires
## for the first, so a panel that shows one unit keeps working.
signal units_selected(instances: Array[UnitInstance])
signal building_instance_selected(instance: BuildingInstance)
signal wall_segment_selected(segment: WallSegment)
signal hex_selected(coord: Vector2i)
signal selection_cleared
signal patrol_recording_changed(is_recording: bool, waypoint_count: int)
## Player-facing, already-worded message about an order that could not be
## carried out — today only "no route" (relayed from
## UnitOrderController.move_order_unreachable). Relayed rather than wired
## straight from UnitOrderController to MainHUD: MainHUD already holds this
## controller as the player's command surface, and giving it a second
## NodePath into the movement layer would widen an already-wide class for
## one toast. The wording lives here because this is the class that talks to
## the player; UnitOrderController stays UI-agnostic and emits raw data.
signal order_feedback(message: String)

const _SELECTION_RING_RADIUS := 16.0
const _SELECTION_RING_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const _PATROL_PREVIEW_COLOR := Color(0.9, 0.85, 0.2, 0.9)
const _WALL_HIGHLIGHT_COLOR := Color(1.0, 0.9, 0.2, 0.9)  ## Same gold as _SELECTION_RING_COLOR — one shared "this is selected" language regardless of what kind of thing it is.
const _WALL_CLICK_TOLERANCE := 24.0  ## Max distance (world units) from a wall segment's own line (hex_a center to hex_b center) a click still counts as "on" it. Small relative to HexCoord.HEX_SIZE (512).
## Screen pixels the mouse must travel with the left button held before a press
## becomes a box selection instead of a click.
const _BOX_DRAG_THRESHOLD_PX := 10.0
## World units between figures when a group is ordered to one point — ~25 m,
## so a squad of sixteen stands in a block about 100 m across rather than on one
## spot, which also keeps a group ordered to a wall piece inside a bow's reach
## of it (WallDefenseController.RANGED_REACH_METRES 200 m).
const _FORMATION_SPACING := 2.5
const _BOX_FILL_COLOR := Color(1.0, 0.9, 0.2, 0.12)
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

var _selected_hex := Vector2i.ZERO
var _has_selected_hex := false
var _selected_unit: UnitInstance
var _selected_units: Array[UnitInstance] = []  ## Every unit in the current selection; _selected_unit is its first.
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _press_ctrl_held: bool = false
var _left_held: bool = false
var _box_active: bool = false
var _group_marker: Node2D
var _group_marker_shown: bool = false  ## Whether the marker drew something last frame, so it is redrawn once more to clear.
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
		_unit_order_controller.move_order_unreachable.connect(_on_move_order_unreachable)
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

	_group_marker = Node2D.new()
	_group_marker.draw.connect(_draw_group_marker)
	add_child(_group_marker)

func get_selected_unit() -> UnitInstance:
	return _selected_unit

func get_selected_units() -> Array[UnitInstance]:
	return _selected_units.duplicate()

## Selects `instances` as a group (a HUD "select army" button, or a drag-box).
func select_units(instances: Array[UnitInstance]) -> void:
	var alive: Array[UnitInstance] = []
	for instance in instances:
		if not instance.is_destroyed():
			alive.append(instance)
	if alive.is_empty():
		clear_selection()
		return
	if alive.size() == 1:
		_select_unit(alive[0])
		return
	_select_unit(alive[0])
	_selected_units = alive
	_selection_ring.visible = false
	units_selected.emit(alive.duplicate())

## Ctrl-click removes one member from a multi-unit selection. A single selected
## unit stays selected, so Ctrl-click cannot leave the player with an accidental
## empty selection.
func deselect_unit(instance: UnitInstance) -> bool:
	if _selected_units.size() <= 1 or not _selected_units.has(instance):
		return false
	_selected_units.erase(instance)
	select_units(_selected_units.duplicate())
	return true

func is_recording_patrol() -> bool:
	return _is_recording_patrol

func get_patrol_waypoint_count() -> int:
	return _patrol_waypoints.size()

func _unhandled_input(event: InputEvent) -> void:
	if _build_placement_controller and _build_placement_controller.is_placing():
		return
	if _wall_placement_controller and _wall_placement_controller.is_placing():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Decided on release: a press that travels becomes a box selection.
			_left_held = true
			_box_active = false
			_press_screen = event.position
			_press_world = get_global_mouse_position()
			_press_ctrl_held = event.ctrl_pressed
		elif _left_held:
			_left_held = false
			if _box_active:
				_box_active = false
				_select_in_box(_press_world, get_global_mouse_position())
			else:
				_on_left_click(_press_world, event.ctrl_pressed or _press_ctrl_held)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _left_held:
		if not _box_active and event.position.distance_to(_press_screen) > _BOX_DRAG_THRESHOLD_PX and not _is_recording_patrol:
			_box_active = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_right_click(get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _is_recording_patrol:
			_cancel_patrol_recording()
		else:
			clear_selection()

func _on_left_click(world_pos: Vector2, ctrl_pressed: bool = false) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	if _is_recording_patrol:
		_patrol_waypoints.append(coord)
		_patrol_waypoint_locals.append(world_pos - HexCoord.axial_to_world(coord))
		_update_patrol_preview()
		patrol_recording_changed.emit(true, _patrol_waypoints.size())
		return
	_select_at(coord, world_pos, ctrl_pressed)

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
	var wall := _closest_wall_within_tolerance(world_pos) if _wall_manager else null
	if wall and not wall.is_breached() and not _selected_units.is_empty() and _unit_order_controller:
		var accepted := 0
		for instance in _selected_units:
			if _unit_order_controller.issue_wall_move_order(instance, wall, world_pos):
				accepted += 1
		order_feedback.emit("%d squads ordered onto the wall. Use Patrol perimeter to walk connected walls." % accepted)
		return
	if _selected_units.size() > 1 and _unit_order_controller:
		var columns := int(ceil(sqrt(float(_selected_units.size()))))
		for i in _selected_units.size():
			var slot := Vector2(float(i % columns) - float(columns - 1) * 0.5, float(i / columns) - float(columns - 1) * 0.5) * _FORMATION_SPACING
			var target_world := world_pos + slot
			var target_coord := _hex_grid_map.world_to_coord(target_world)
			_unit_order_controller.issue_move_order(_selected_units[i], target_coord, target_world - HexCoord.axial_to_world(target_coord))
		return
	if _selected_unit and _unit_order_controller:
		var local_offset := world_pos - HexCoord.axial_to_world(coord)
		_unit_order_controller.issue_move_order(_selected_unit, coord, local_offset)

func _select_at(coord: Vector2i, world_pos: Vector2, ctrl_pressed: bool = false) -> void:
	if _unit_manager:
		var unit := _closest_unit_within_tolerance(world_pos)
		if unit:
			if ctrl_pressed and deselect_unit(unit):
				return
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
				select_building(building)
				return
	clear_selection()
	_selected_hex = coord
	_has_selected_hex = true
	hex_selected.emit(coord)

func _select_in_box(world_a: Vector2, world_b: Vector2) -> void:
	if not _unit_manager:
		return
	var box := Rect2(world_a, Vector2.ZERO).expand(world_b)
	var picked: Array[UnitInstance] = []
	for instance in _unit_manager.get_all_units():
		if not instance.is_destroyed() and box.has_point(_unit_draw_position(instance)):
			picked.append(instance)
	select_units(picked)

func _draw_group_marker() -> void:
	var pixel := 1.0 / maxf(0.0001, get_viewport().get_canvas_transform().get_scale().x)
	if not _selected_units.is_empty() and _hex_grid_map:
		var cursor := get_global_mouse_position()
		var coord := _hex_grid_map.world_to_coord(cursor)
		var cell := _hex_grid_map.get_cell(coord)
		if cell:
			var sub := HexCoord.sub_hex_index_within(coord, cursor)
			var height := SubHexTerrainQuery.elevation_metres(coord, sub)
			var passable := SubHexTerrainQuery.is_passable_at(coord, cursor, cell.is_passable()) and not ElevationLevels.is_impassable(cell.height_level())
			var biome := SubHexTerrainQuery.biome_at(coord, cursor, cell.biome_type)
			var description := "%.0f m · %s" % [height, "Open ground" if passable else "Impassable ground"]
			if biome == GameEnums.BiomeType.WATERWAY:
				description = "%.0f m · River: bridge required" % height
			_group_marker.draw_set_transform(cursor + Vector2(16, 22) * pixel, 0.0, Vector2.ONE * pixel)
			_group_marker.draw_string(ThemeDB.fallback_font, Vector2(1, 1), description, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
			_group_marker.draw_string(ThemeDB.fallback_font, Vector2.ZERO, description, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if passable else HUDStyles.DANGER_COLOR)
			_group_marker.draw_set_transform(Vector2.ZERO)
	if _box_active:
		var box := Rect2(_press_world, Vector2.ZERO).expand(get_global_mouse_position())
		_group_marker.draw_rect(box, _BOX_FILL_COLOR, true)
		_group_marker.draw_rect(box, _SELECTION_RING_COLOR, false, 2.0 * pixel)
	if _selected_units.size() > 1:
		for instance in _selected_units:
			_group_marker.draw_arc(_unit_draw_position(instance), 7.0 * pixel, 0.0, TAU, 12, _SELECTION_RING_COLOR, 2.0 * pixel)

func _select_unit(instance: UnitInstance) -> void:
	_has_selected_hex = false
	_selected_units = [instance]
	_selected_unit = instance
	_selected_building = null
	_selected_wall = null
	# Reset back to the unit-scoped radius in case the previous selection
	# was a (much bigger) building — see select_building()'s own comment on
	# why that one uses a different radius from this shared ring.
	_selection_ring.points = _ring_points(_SELECTION_RING_RADIUS)
	# The ring uses the unit's own real, continuously-moving position, not
	# its hex center — same "use the real world position, not a hex-bucket
	# proxy" fix _closest_unit_within_tolerance() applies to hit-testing.
	_selection_ring.position = _unit_draw_position(instance)
	_selection_ring.visible = true
	_wall_highlight.visible = false
	unit_selected.emit(_selected_unit)

func select_building(instance: BuildingInstance) -> void:
	_has_selected_hex = false
	_selected_units.clear()
	_selected_unit = null
	_selected_building = instance
	_selected_wall = null
	# TacticalHexView.BUILDING_SELECTION_RING_RADIUS is derived from
	# BUILDING_HALF_SIZE, so this ring stays sized to the building's box
	# (rather than the unit-scoped _SELECTION_RING_RADIUS, which would
	# render inside the box) automatically if that box size ever changes.
	_selection_ring.scale = Vector2.ONE
	_selection_ring.points = _ring_points(TacticalHexView.BUILDING_SELECTION_RING_RADIUS)
	_selection_ring.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	_selection_ring.visible = true
	_wall_highlight.visible = false
	building_instance_selected.emit(instance)

func _select_wall(segment: WallSegment) -> void:
	_has_selected_hex = false
	_selected_units.clear()
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
	var closest_dist: float = minf(_WALL_CLICK_TOLERANCE, 6.0 / maxf(0.01, get_viewport().get_canvas_transform().get_scale().x))
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
	var radius := minf(_UNIT_CLICK_TOLERANCE, 14.0 / maxf(0.01, get_viewport().get_canvas_transform().get_scale().x))
	var closest_dist: float = radius * radius
	for instance in _unit_manager.get_all_units():
		var origin := _unit_draw_position(instance)
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

## design_doc.md §2.1's "Going dark". Same thin-wrapper shape as the repair
## pair above — the two directions are separate calls rather than one
## toggle() so UnitPanelView can label and gate the button with the real
## rejection reason before the player presses it, which a single toggle
## could not report.
func get_selected_building_power_down_error() -> String:
	if _selected_building and _building_manager:
		return _building_manager.get_power_down_error(_selected_building)
	return "Nothing selected."

func power_down_selected_building() -> bool:
	if _selected_building and _building_manager:
		return _building_manager.power_down_building(_selected_building)
	return false

func get_selected_building_restart_error() -> String:
	if _selected_building and _building_manager:
		return _building_manager.get_restart_error(_selected_building)
	return "Nothing selected."

func restart_selected_building() -> bool:
	if _selected_building and _building_manager:
		return _building_manager.restart_building(_selected_building)
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
	_has_selected_hex = false
	_selected_units.clear()
	_selected_unit = null
	_selected_building = null
	_selected_wall = null
	_selection_ring.visible = false
	_wall_highlight.visible = false
	selection_cleared.emit()

## --- Order commands, called by UnitPanelView's buttons ---------------------

func order_hold() -> void:
	if not _unit_order_controller:
		return
	for instance in _selected_units:
		_unit_order_controller.issue_hold_order(instance)

func order_garrison() -> void:
	if _selected_unit and _unit_order_controller:
		for instance in _selected_units:
			_unit_order_controller.issue_garrison_order(instance)

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
		for instance in _selected_units:
			_unit_order_controller.issue_patrol_order(instance, _patrol_waypoints, _patrol_waypoint_locals)
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
	if _selected_units.size() > 1 and _selected_units.has(instance):
		_selected_units.erase(instance)
		select_units(_selected_units.duplicate())
		return
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
		_selection_ring.position = _unit_draw_position(_selected_unit)
		_selection_ring.scale = Vector2.ONE * (10.0 / _SELECTION_RING_RADIUS / maxf(0.01, get_viewport().get_canvas_transform().get_scale().x))
	var showing := _box_active or not _selected_units.is_empty()
	if showing or _group_marker_shown:
		_group_marker.queue_redraw()
	_group_marker_shown = showing

## UnitPanelView has no direct reference to UnitOrderController (this
## controller owns that), so an order change reaches it by re-emitting the
## SAME unit_selected signal a fresh selection uses — UnitPanelView
## re-renders identically either way. Only for the currently selected unit.
## Names the unit, since several can be under orders at once and a bare
## "no route" would not say which one stopped.
func _on_move_order_unreachable(instance: UnitInstance, _destination: Vector2i) -> void:
	var display_name := instance.definition.display_name if instance and instance.definition else "Unit"
	order_feedback.emit("%s cannot find a route to that location." % display_name)

func _on_unit_order_issued(instance: UnitInstance, _order: GameEnums.UnitOrderType) -> void:
	if instance == _selected_unit:
		unit_selected.emit(instance)

func _ring_points(radius: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(radius * cos(angle), radius * sin(angle)))
	return points

func order_wall_patrol() -> void:
	if not _wall_manager or not _unit_order_controller:
		return
	for instance in _selected_units:
		var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		var best: WallSegment = null
		var distance := INF
		for segment in _wall_manager.get_segments():
			if segment.is_breached():
				continue
			var candidate := world.distance_to(Geometry2D.get_closest_point_to_segment(world, segment.point_a, segment.point_b))
			if candidate < distance:
				best = segment
				distance = candidate
		if best:
			_unit_order_controller.issue_wall_move_order(instance, best, world, true)
	order_feedback.emit("Squads will mount the nearest intact wall and patrol its connected perimeter.")

func get_selected_hex() -> Vector2i:
	return _selected_building.hex_coord if _selected_building else _selected_hex

func has_selected_hex() -> bool:
	return _has_selected_hex

func set_hex_power(coord: Vector2i, enabled: bool) -> void:
	if not _building_manager:
		return
	var changed := _building_manager.set_hex_power(coord, enabled)
	order_feedback.emit("%d buildings %s in this hex." % [changed, "restarting" if enabled else "switched off"])
	clear_selection()
	_has_selected_hex = true
	_selected_hex = coord
	hex_selected.emit(coord)

func _unit_draw_position(instance: UnitInstance) -> Vector2:
	var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	if instance.on_wall:
		world.y -= WallVisuals.TACTICAL_WALL_WIDTH * 0.25
	return world
