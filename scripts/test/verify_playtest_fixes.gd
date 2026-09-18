extends Node

var _map: HexGridMap
var _units: UnitManager
var _orders: UnitOrderController
var _walls: WallManager
var _hordes: HordeManager
var _combat: CombatCoordinator
var _commands: UnitCommandController
var _failures: Array[String] = []

func _ready() -> void:
	_map = HexGridMap.new()
	_map.name = "Map"
	_map.auto_generate_on_ready = false
	add_child(_map)
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(Vector2i.ZERO, 3):
		cells[coord] = HexCell.new(coord)
	_map.load_cells(cells)
	_walls = WallManager.new()
	_walls.name = "Walls"
	add_child(_walls)
	_units = UnitManager.new()
	_units.name = "Units"
	add_child(_units)
	_orders = UnitOrderController.new()
	_orders.name = "Orders"
	_orders.hex_grid_map_path = NodePath("../Map")
	_orders.unit_manager_path = NodePath("../Units")
	_orders.wall_manager_path = NodePath("../Walls")
	add_child(_orders)
	_orders.set_process(false)
	_hordes = HordeManager.new()
	_hordes.name = "Hordes"
	_hordes.wall_manager_path = NodePath("../Walls")
	add_child(_hordes)
	_hordes.set_process(false)
	_combat = CombatCoordinator.new()
	_combat.unit_manager_path = NodePath("../Units")
	_combat.horde_manager_path = NodePath("../Hordes")
	add_child(_combat)
	_combat.set_process(false)
	_commands = UnitCommandController.new()
	_commands.hex_grid_map_path = NodePath("../Map")
	_commands.unit_manager_path = NodePath("../Units")
	_commands.unit_order_controller_path = NodePath("../Orders")
	_commands.wall_manager_path = NodePath("../Walls")
	add_child(_commands)
	_commands.set_process(false)
	_check_arrival_and_frame_rates()
	_check_local_patrol()
	_check_wall_access_and_restore()
	_check_connected_wall_walk()
	_check_combat_distance()
	_check_single_zombie_death()
	_check_pursuit_slots()
	_check_stationary_close_targets()
	_check_ctrl_deselect()
	_check_mobile_vision()
	await _check_paused_camera()
	if _failures.is_empty():
		print("All playtest regression checks passed: stable movement, local patrol, wall access/save, contact range, mobile fog.")
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _unit(position: Vector2, type: GameEnums.UnitType = GameEnums.UnitType.TOXOPHILITE) -> UnitInstance:
	var entries: Array[UnitSaveEntry] = [UnitSaveEntry.new(type, Vector2i.ZERO, 1, 24.0, GameEnums.UnitOrderType.HOLD, Vector2i.ZERO, [], 0, position)]
	_units.load_save_entries(entries, 2)
	return _units.get_all_units()[0]

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _check_arrival_and_frame_rates() -> void:
	for fps in [30, 60, 120]:
		var unit := _unit(Vector2(-100, 50))
		_orders.issue_move_order(unit, Vector2i.ZERO, Vector2(100, 50))
		var previous := unit.local_position
		for frame in fps * 8:
			_orders.advance_orders(1.0 / fps)
			_check(unit.local_position.x >= previous.x - 0.001, "Movement reversed on open ground at %d fps" % fps)
			_check(absf(unit.local_position.y - 50.0) < 0.001, "Open-ground movement wobbled at %d fps" % fps)
			_check(previous.distance_to(unit.local_position) <= MovementStepper.BASE_MOVE_SPEED * 1.2 / fps + 0.001, "Movement exceeded its speed budget")
			previous = unit.local_position
		_check(unit.order == GameEnums.UnitOrderType.HOLD and unit.local_position.distance_to(Vector2(100, 50)) < 0.01, "Unit did not settle exactly at its destination")
		_orders.advance_orders(60.0)
		_check(unit.local_position == previous, "Holding unit drifted")

func _check_local_patrol() -> void:
	var unit := _unit(Vector2(-80, 0))
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
	var offsets: Array[Vector2] = [Vector2(-80, 0), Vector2(80, 0)]
	_orders.issue_patrol_order(unit, coords, offsets)
	var east := false
	var west := false
	for i in 900:
		_orders.advance_orders(1.0 / 60.0)
		east = east or unit.local_position.x >= 79.0
		west = west or (east and unit.local_position.x <= -79.0)
	_check(east and west, "Patrol skipped waypoints within one hex")

func _check_wall_access_and_restore() -> void:
	var wall := WallSegment.new(Vector2i.ZERO, Vector2i.ZERO, Vector2(0, -30), Vector2(0, 30), WallCatalog.WOODEN, 1)
	var segments: Array[WallSegment] = [wall]
	_walls.load_save_state(segments, 2)
	var unit := _unit(Vector2(-40, 0))
	_orders.issue_move_order(unit, Vector2i.ZERO, Vector2(40, 0))
	var crossed_wall := false
	for i in 600:
		var before := unit.local_position
		_orders.advance_orders(1.0 / 60.0)
		crossed_wall = crossed_wall or Geometry2D.segment_intersects_segment(before, unit.local_position, wall.point_a, wall.point_b) != null
	_check(not crossed_wall and unit.local_position.distance_to(Vector2(40, 0)) < 0.01, "Ground route crossed an intact wall or failed to go around it")
	_check(_orders.issue_wall_move_order(unit, wall, Vector2.ZERO, true), "Wall patrol order was rejected")
	for i in 240:
		_orders.advance_orders(1.0 / 60.0)
	_check(unit.on_wall and unit.order == GameEnums.UnitOrderType.PATROL, "Unit failed to mount and patrol the wall")
	var entries := _units.get_save_entries()
	_units.load_save_entries(entries, 2)
	unit = _units.get_all_units()[0]
	_check(unit.on_wall and unit.wall_target_active and not unit.wall_patrol_route.is_empty(), "Wall patrol did not survive save/load")
	wall.current_hp = 0.0
	_orders.advance_orders(0.1)
	_check(not unit.on_wall and not unit.wall_target_active, "Unit continued walking on a breached wall")
	_walls.load_save_state([], 1)

func _check_combat_distance() -> void:
	var unit := _unit(Vector2.ZERO)
	var far := _hordes.spawn_local_horde(Vector2i.ZERO, 100, Vector2(300, 0))
	_combat.advance_combat(20.0)
	_check(unit.current_hp == 24.0 and far.size == 100, "Combat damaged a distant target sharing the hex")
	_hordes.remove_horde(far)
	var near := _hordes.spawn_local_horde(Vector2i.ZERO, 100, Vector2(12, 0))
	_combat.advance_combat(20.0)
	_check(near.size < 100 and unit.current_hp == 24.0, "Ranged fire failed or a distant zombie inflicted melee damage")
	var wounded_size := near.size
	_combat.advance_combat(0.1)
	_check(near.size == wounded_size, "Unit fired twice without its cooldown")
	near.local_position = Vector2(1, 0)
	_combat.advance_combat(20.0)
	_check(unit.current_hp < 24.0, "Contact-range zombies dealt no damage")
	_hordes.remove_horde(near)

func _check_single_zombie_death() -> void:
	_unit(Vector2.ZERO)
	var lone := _hordes.spawn_local_horde(Vector2i.ZERO, 1, Vector2.ZERO)
	_combat.advance_combat(0.1)
	_check(not _hordes.get_all_hordes().has(lone), "A lethal shot left one zombie alive and walking")

func _check_pursuit_slots() -> void:
	var unit := _unit(Vector2.ZERO)
	var first := _hordes.spawn_local_horde(Vector2i.ZERO, 20, Vector2(-20, 0))
	var second := _hordes.spawn_local_horde(Vector2i.ZERO, 20, Vector2(20, 0))
	_combat.advance_combat(0.1)
	_check(first.has_combat_target and second.has_combat_target, "Nearby hordes did not acquire a shared unit")
	_check(first.combat_target.distance_to(second.combat_target) > 0.1, "Hordes pursuing one unit received the same stacking destination")
	_check(first.combat_target.distance_to(HexCoord.axial_to_world(unit.hex_coord) + unit.local_position) <= CombatCoordinator.MELEE_REACH, "First pursuit slot fell outside melee contact")
	_check(second.combat_target.distance_to(HexCoord.axial_to_world(unit.hex_coord) + unit.local_position) <= CombatCoordinator.MELEE_REACH, "Second pursuit slot fell outside melee contact")
	_hordes.remove_horde(first)
	_hordes.remove_horde(second)

func _check_connected_wall_walk() -> void:
	var corners: Array[Vector2] = [Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]
	var segments: Array[WallSegment] = []
	for i in 4:
		segments.append(WallSegment.new(Vector2i.ZERO, Vector2i.ZERO, corners[i], corners[(i + 1) % 4], WallCatalog.WOODEN, i + 1))
	_walls.load_save_state(segments, 5)
	var unit := _unit(Vector2(0, -30))
	unit.on_wall = true
	_orders.issue_wall_move_order(unit, segments[2], Vector2(0, 30))
	for i in 600:
		_orders.advance_orders(1.0 / 60.0)
		_check(WallWalkRoute.segment_at(_walls, unit.local_position) != null, "Mounted unit cut a corner across open ground")
	_check(unit.on_wall and unit.order == GameEnums.UnitOrderType.HOLD and unit.local_position.distance_to(Vector2(0, 30)) < 0.01, "Mounted move failed to reach another connected wall")
	var circuit := WallWalkRoute.perimeter(_walls, segments[0], Vector2(0, -30))
	var distance := 0.0
	for i in range(1, circuit.size()):
		distance += circuit[i - 1].distance_to(circuit[i])
	_check(is_equal_approx(distance, 240.0) and circuit[0] == circuit[-1], "Closed perimeter did not traverse every edge exactly once")
	_walls.load_save_state([], 1)

func _check_mobile_vision() -> void:
	var unit := _unit(Vector2.ZERO)
	var fog := FogOfWarManager.new()
	fog.hex_grid_map_path = NodePath("../Map")
	fog.unit_manager_path = NodePath("../Units")
	add_child(fog)
	fog.set_process(false)
	var occupied := Vector2i(2, 0)
	# Simulate a position between macro-route waypoints, including radius zero.
	unit.local_position = HexCoord.axial_to_world(occupied)
	fog.recompute()
	_check(fog.is_visible(occupied), "Mobile vision did not reveal the unit's physical hex")
	unit.local_position = HexCoord.axial_to_world(Vector2i(1, 0)) * 0.499
	fog.recompute()
	_check(fog.is_visible(Vector2i(1, 0)), "Fog concealed enemies immediately across a border from infantry")
	unit.local_position = Vector2.ZERO
	fog.recompute()
	fog.queue_free()

func _check_stationary_close_targets() -> void:
	var unit := _unit(Vector2.ZERO)
	var horde := _hordes.spawn_local_horde(Vector2i.ZERO, 100, Vector2.ZERO, 30.0)
	_combat.advance_combat(0.1)
	_check(horde.size < 100, "An overlapping new zombie was untargetable during contact grace")
	var previous := horde.size
	for i in 3:
		_combat.advance_combat(CombatCoordinator.CONTACT_INTERVAL)
		_check(horde.size < previous, "A stationary squad needed a range re-entry to fire again")
		previous = horde.size
	_check(unit.local_position == Vector2.ZERO, "Stationary-fire test moved its squad")
	_hordes.remove_horde(horde)
	var swarm := ZombieSwarm.new(7)
	swarm.anchor = Vector2(100, 100)
	swarm.spread = 2.0
	swarm.set_count(5)
	var before := swarm.position_at(0)
	swarm.move_anchor(Vector2(160, 120))
	_check(swarm.position_at(0).distance_to(before + Vector2(60, 20)) < 0.001, "Visible crowd lagged behind its combat body")

func _check_ctrl_deselect() -> void:
	var first := _unit(Vector2(-20, 0))
	var second := _unit(Vector2(20, 0))
	_commands.select_units([first, second])
	_check(_commands.deselect_unit(first), "Ctrl-click could not remove a unit from a group")
	var remaining := _commands.get_selected_units()
	_check(remaining.size() == 1 and remaining[0] == second, "Ctrl-click removed the wrong selected unit")
	_check(not _commands.deselect_unit(second), "Ctrl-click cleared a one-unit selection")

func _check_paused_camera() -> void:
	var camera := CameraController.new()
	camera.edge_pan_enabled = false
	add_child(camera)
	TickManager.set_speed_index(0)
	for i in 3:
		await get_tree().process_frame
	for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		var before := camera.position
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		Input.parse_input_event(event)
		for i in 8:
			await get_tree().process_frame
		event.pressed = false
		Input.parse_input_event(event)
		_check(camera.position.distance_to(before) > 0.0, "Camera key %d did not pan while paused" % key)
	camera.queue_free()
