class_name UnitOrderController
extends Node


## Player orders, cached local routes, and continuous movement in world space.

signal unit_order_issued(instance: UnitInstance, order: GameEnums.UnitOrderType)
## No route exists from where this unit is standing to `destination` — the
## goal is impassable, off-map, or walled/sealed off from it. Emitted once
## per (unit, destination), not once per failed replan: without a route the
## unit simply stands still, which is indistinguishable from a bug unless
## something says so ("if you attempt to tell a unit to go to a place and it
## cant find a valid path there, there should be a message displayed on the
## screen momentarily", user report). UnitCommandController relays it to the
## HUD; nothing here knows what a toast is.
signal move_order_unreachable(instance: UnitInstance, destination: Vector2i)
signal unit_arrived(instance: UnitInstance, coord: Vector2i)
signal unit_moved(instance: UnitInstance, from_coord: Vector2i, to_coord: Vector2i)

@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — HexPathfinder's road/rail/canal discount (a continuous speed bonus, see MovementStepper), and the Zone of Control read _is_friendly_hex() gates Garrison/Hold healing on. Unset skips both.
@export var building_manager_path: NodePath  ## Optional — local obstacle avoidance: buildings steer continuous movement around them regardless of Tactical hydration.
@export var local_detail_manager_path: NodePath  ## Retained for saved scenes; visual prop hydration does not determine movement.
@export var tech_manager_path: NodePath  ## Optional — the SPECIAL-role movement upgrade (UnitUpgrades.move_speed_multiplier()). Unset means units move at their raw UnitDefinition speed.
@export var wall_manager_path: NodePath  ## Optional — strategic route wall-avoidance, fed into HexPathfinder.find_path() so a unit's route goes around an un-breached wall. Unset means no wall-awareness.

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _tech_manager: TechManager
var _wall_manager: WallManager
var _logic_tick_timer: float = 0.0
var _navigation := LocalUnitNavigation.new()
var _local_routes: Dictionary = {}
var _route_targets: Dictionary = {}
var _route_revisions: Dictionary = {}

const LOGIC_TICK_SECONDS: float = 20.0  ## Matches HordeManager.LOGIC_TICK_SECONDS. No longer governs movement itself.

const REPLAN_RETRY_SECONDS: float = 2.0

var _replan_backoff: Dictionary = {}       ## Transient — unit id -> seconds until the next replan attempt is allowed.
var _unreachable_reported: Dictionary = {} ## Transient — unit id -> Vector2i destination already announced, so move_order_unreachable fires once per order rather than once per retry.

## "Military units get increased movement speed" (Day) — no exact design
## number, a placeholder balancing multiplier. No Night-time penalty — Night
## is plain baseline speed (this constant simply doesn't apply). The
## matching damage bonus lives in CombatCoordinator.DAY_DAMAGE_MULTIPLIER —
## this class has no combat code to fold it into.
const DAY_MOVE_SPEED_MULTIPLIER: float = 1.2

## A fraction of max_hp (not a flat number) so a Tier 5 unit's much larger
## HP pool doesn't heal proportionally slower than a Tier 0 unit's. Ticks on
## LOGIC_TICK_SECONDS, applied only to HOLD/GARRISON units.
const GARRISON_REGEN_FRACTION_PER_TICK: float = 0.05

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  ## Background-simulation infrastructure — shouldn't freeze if the SceneTree is ever paused.
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_trained.connect(_clear_cached_route)
		_unit_manager.unit_removed.connect(_clear_cached_route)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)

	_navigation.setup(_hex_grid_map, _building_manager, _wall_manager, _logistics_network)

func _process(delta: float) -> void:
	advance_orders(delta)

func advance_orders(delta: float) -> void:
	if not _unit_manager:
		return
	var units := _unit_manager.get_all_units()

	# Continuous movement — every frame, every unit under an order that
	# actually moves (MOVE/ATTACK_MOVE/PATROL); a no-op for HOLD/GARRISON.
	for instance in units:
		if not instance.is_destroyed():
			_advance_unit(instance, delta)

	# The one remaining periodic side-effect (Garrison/Hold regen).
	_logic_tick_timer += delta
	while _logic_tick_timer >= LOGIC_TICK_SECONDS:
		_logic_tick_timer -= LOGIC_TICK_SECONDS
		for instance in units:
			if instance.order == GameEnums.UnitOrderType.HOLD or instance.order == GameEnums.UnitOrderType.GARRISON:
				_regen_if_friendly(instance)

## --- Order issuing (player-facing API — called by UnitCommandController) --

## `destination_local` — the exact offset within `destination`'s hex to
## walk to, ZERO (the hex center) if the caller doesn't need sub-hex
## precision. See UnitInstance.move_target_local's own doc comment.
func issue_move_order(instance: UnitInstance, destination: Vector2i, destination_local: Vector2 = Vector2.ZERO) -> void:
	instance.on_wall = false
	instance.pending_garrison_arrival = false  ## A fresh player order always overrides an in-flight "route to garrison" — see that field's own doc comment.
	_set_order(instance, GameEnums.UnitOrderType.MOVE)
	instance.move_target = destination
	instance.move_target_local = destination_local
	instance.path.clear()

func issue_attack_move_order(instance: UnitInstance, destination: Vector2i, destination_local: Vector2 = Vector2.ZERO) -> void:
	instance.on_wall = false
	instance.pending_garrison_arrival = false
	_set_order(instance, GameEnums.UnitOrderType.ATTACK_MOVE)
	instance.move_target = destination
	instance.move_target_local = destination_local
	instance.path.clear()

func issue_hold_order(instance: UnitInstance) -> void:
	instance.pending_garrison_arrival = false
	_set_order(instance, GameEnums.UnitOrderType.HOLD)
	instance.path.clear()

## "Assign a unit to a building for a stationary defense bonus" — routes the
## unit to the nearest OPERATIONAL Town Hall or Garrison building
## (BuildingManager.find_nearest_building()) first; the real payoffs
## (healing, incoming-damage reduction, both keyed off instance.order ==
## GARRISON wherever they're computed) only apply once it's actually there.
## A unit already standing on a Town Hall/Garrison hex, or with no such
## building anywhere yet, gets the stance applied immediately in place.
##
## Does NOT call issue_move_order() for the routing case — that function
## unconditionally clears pending_garrison_arrival (a fresh player MOVE
## order should always cancel an in-flight garrison-route), which would
## immediately undo the flag this function needs to set.
func issue_garrison_order(instance: UnitInstance) -> void:
	instance.on_wall = false
	var target: BuildingInstance = null
	if _building_manager:
		target = _building_manager.find_nearest_building(instance.hex_coord, [GameEnums.BuildingType.TOWN_HALL, GameEnums.BuildingType.GARRISON])
	if not target or target.hex_coord == instance.hex_coord:
		instance.pending_garrison_arrival = false
		_set_order(instance, GameEnums.UnitOrderType.GARRISON)
		instance.path.clear()
		return
	instance.pending_garrison_arrival = true
	_set_order(instance, GameEnums.UnitOrderType.MOVE)
	instance.move_target = target.hex_coord
	instance.move_target_local = Vector2.ZERO
	instance.path.clear()

## `waypoints` must be non-empty — a no-op (reported via return value)
## otherwise. `waypoint_locals` — index-aligned with `waypoints`, the exact
## offset within each waypoint's hex to actually visit; empty (the default)
## means every leg targets its own hex center.
func issue_patrol_order(instance: UnitInstance, waypoints: Array[Vector2i], waypoint_locals: Array[Vector2] = []) -> bool:
	if waypoints.is_empty():
		return false
	instance.on_wall = false
	instance.pending_garrison_arrival = false
	_set_order(instance, GameEnums.UnitOrderType.PATROL)
	instance.patrol_waypoints = waypoints.duplicate()
	instance.patrol_waypoint_locals = waypoint_locals.duplicate()
	instance.patrol_target_index = 0
	instance.path.clear()
	return true

## Every order path routes through here, so clearing the transient
## route-failure state in one place covers move/attack-move/patrol/garrison
## alike — a fresh order deserves a fresh attempt and, if it fails too, a
## fresh message.
func _set_order(instance: UnitInstance, order: GameEnums.UnitOrderType) -> void:
	instance.order = order
	_local_routes.erase(instance.id)
	_route_targets.erase(instance.id)
	_route_revisions.erase(instance.id)
	instance.wall_patrol_route.clear()
	instance.wall_target_active = false
	_replan_backoff.erase(instance.id)
	_unreachable_reported.erase(instance.id)
	unit_order_issued.emit(instance, order)

## What a one-shot MOVE/ATTACK_MOVE order reverts to on arrival — HOLD,
## unless issue_garrison_order() routed this unit here specifically to
## garrison (pending_garrison_arrival), in which case arriving applies the
## real GARRISON stance instead of just stopping.
func _revert_on_arrival(instance: UnitInstance) -> void:
	if instance.pending_garrison_arrival:
		instance.pending_garrison_arrival = false
		_set_order(instance, GameEnums.UnitOrderType.GARRISON)
	else:
		_set_order(instance, GameEnums.UnitOrderType.HOLD)

## --- Continuous movement ----------------------------------------------------

func _advance_unit(instance: UnitInstance, delta: float) -> void:
	if instance.on_wall and not WallWalkRoute.segment_at(_wall_manager, HexCoord.axial_to_world(instance.hex_coord) + instance.local_position):
		instance.on_wall = false
	if instance.wall_target_active:
		_advance_wall_order(instance, delta)
		return
	match instance.order:
		GameEnums.UnitOrderType.MOVE, GameEnums.UnitOrderType.ATTACK_MOVE:
			_advance_toward(instance, instance.move_target, instance.move_target_local, true, delta)
		GameEnums.UnitOrderType.PATROL:
			_advance_patrol(instance, delta)
		_:
			pass


func _advance_toward(instance: UnitInstance, destination: Vector2i, destination_local: Vector2, revert_to_hold_on_arrival: bool, delta: float) -> void:
	if delta <= 0.0:
		return
	var target := HexCoord.axial_to_world(destination) + destination_local
	var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	# Nearby clicks route against physical geometry, including the inside of a
	# border wall. A macro edge must not send a squad around the entire town.
	var nearby := world.distance_to(target) <= HexCoord.HEX_SIZE * 2.0
	if not nearby and instance.path.is_empty():
		_replan_with_backoff(instance, destination, delta)
		if instance.path.is_empty():
			return
	var leg := target
	if not instance.path.is_empty():
		var next_coord: Vector2i = instance.path[0]
		leg = HexCoord.axial_to_world(next_coord) + _crossing_offset(instance.hex_coord, next_coord)
	if _route_revisions.get(instance.id, -1) != _navigation.revision:
		_local_routes.erase(instance.id)
	if _local_routes.has(instance.id):
		leg = _route_targets[instance.id]
	if _route_targets.get(instance.id) != leg:
		_local_routes.erase(instance.id)
	if not _local_routes.has(instance.id):
		var retry: float = _replan_backoff.get(instance.id, 0.0) - delta
		if retry > 0.0:
			_replan_backoff[instance.id] = retry
			return
		var route := _navigation.find_route(world, leg)
		if route.is_empty() and destination != instance.hex_coord:
			_replan(instance, destination)
			if not instance.path.is_empty():
				var next_coord: Vector2i = instance.path[0]
				leg = HexCoord.axial_to_world(next_coord) + _crossing_offset(instance.hex_coord, next_coord)
				route = _navigation.find_route(world, leg)
		if route.is_empty():
			_replan_backoff[instance.id] = REPLAN_RETRY_SECONDS
			if not _unreachable_reported.has(instance.id):
				_unreachable_reported[instance.id] = destination
				move_order_unreachable.emit(instance, destination)
			return
		_route_revisions[instance.id] = _navigation.revision
		_local_routes[instance.id] = route
		_route_targets[instance.id] = leg
		_replan_backoff.erase(instance.id)
		_unreachable_reported.erase(instance.id)
	var points: PackedVector2Array = _local_routes[instance.id]
	var remaining := delta
	while remaining > 0.0 and not points.is_empty():
		var speed := _movement_speed(instance, instance.hex_coord, HexCoord.world_to_axial(points[0]))
		var distance := world.distance_to(points[0])
		var travel := minf(distance, speed * remaining)
		var next := world.move_toward(points[0], travel)
		# Reject a wall built across an already planned route.
		if _wall_manager and _wall_manager.get_blocking_segment_at_world(world, next, true):
			_local_routes.erase(instance.id)
			return
		world = next
		remaining -= travel / maxf(speed, 0.01)
		_set_world_position(instance, world)
		if distance <= travel + 0.001:
			points.remove_at(0)
		else:
			break
	_local_routes[instance.id] = points
	if not points.is_empty():
		return
	_local_routes.erase(instance.id)
	if world.distance_to(target) <= 0.01:
		instance.path.clear()
		unit_arrived.emit(instance, instance.hex_coord)
		if revert_to_hold_on_arrival:
			_revert_on_arrival(instance)
	elif not instance.path.is_empty():
		instance.path.pop_front()

func _set_world_position(instance: UnitInstance, world: Vector2) -> void:
	var previous := instance.hex_coord
	instance.hex_coord = HexCoord.world_to_axial(world)
	instance.local_position = world - HexCoord.axial_to_world(instance.hex_coord)
	if previous != instance.hex_coord:
		unit_moved.emit(instance, previous, instance.hex_coord)

## On reaching a waypoint, loops immediately to the next one within the SAME
## call whenever the unit is already standing on the current one, so travel
## toward a genuinely unreached leg starts this frame, not next — matters on
## a patrol with many close-together waypoints, where waiting a full
## frame/tick per already-reached waypoint would read as "stuck". `guard`
## bounds the loop to patrol_waypoints.size() iterations — a patrol can
## never need more "already there, advance" steps than it has waypoints, so
## this can't spin forever even if every waypoint shares one hex.
func _advance_patrol(instance: UnitInstance, delta: float) -> void:
	if not instance.has_patrol_waypoints():
		return
	var guard := instance.patrol_waypoints.size()
	while guard > 0:
		instance.patrol_target_index = wrapi(instance.patrol_target_index, 0, instance.patrol_waypoints.size())
		var target: Vector2i = instance.patrol_waypoints[instance.patrol_target_index]
		if instance.hex_coord != target or instance.local_position.distance_to(_patrol_waypoint_local(instance, instance.patrol_target_index)) > 0.01:
			_advance_toward(instance, target, _patrol_waypoint_local(instance, instance.patrol_target_index), false, delta)
			return
		instance.patrol_target_index = wrapi(instance.patrol_target_index + 1, 0, instance.patrol_waypoints.size())
		guard -= 1
	# Every waypoint shares the unit's current hex (a degenerate all-in-one-
	# hex patrol) — nothing left to actually walk toward this frame.

## `patrol_waypoint_locals` is index-aligned with `patrol_waypoints` but
## (same as move_target_local) defaults to empty for any unit/save
## predating this field — out-of-range or missing falls back to ZERO.
func _patrol_waypoint_local(instance: UnitInstance, index: int) -> Vector2:
	if index < instance.patrol_waypoint_locals.size():
		return instance.patrol_waypoint_locals[index]
	return Vector2.ZERO

## Runs _replan() at most every REPLAN_RETRY_SECONDS while it keeps failing,
## and announces the first failure for this order via move_order_unreachable.
## A success clears both, so a unit that later gets a route (wall breached,
## marsh drained) resumes silently.
func _replan_with_backoff(instance: UnitInstance, destination: Vector2i, delta: float) -> void:
	var remaining: float = _replan_backoff.get(instance.id, 0.0) - delta
	if remaining > 0.0:
		_replan_backoff[instance.id] = remaining
		return
	_replan(instance, destination)
	if not instance.path.is_empty():
		_replan_backoff.erase(instance.id)
		_unreachable_reported.erase(instance.id)
		return
	_replan_backoff[instance.id] = REPLAN_RETRY_SECONDS
	if _unreachable_reported.get(instance.id) != destination:
		_unreachable_reported[instance.id] = destination
		move_order_unreachable.emit(instance, destination)

func _replan(instance: UnitInstance, destination: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var path := HexPathfinder.find_path(_hex_grid_map, instance.hex_coord, destination, _logistics_network, _wall_manager, true)
	if path.size() > 1:
		path.remove_at(0)  # path[0] is the unit's own current hex.
		instance.path = path

## SubHexPortalGraph.portal_offset_for_step() needs a live HexGridMap — same
## null-guard convention _movement_speed() already applies to the same field.
## A unit is stopped by solid wall but walks through a Gate — see
## WallManager.get_blocking_segment()'s own `ignore_gates` doc comment.
##
## Where within `to_coord` this crossing should aim: the Gate's own midpoint
## if one stands on this edge, otherwise the sub-hex portal
## (SubHexPortalGraph, Sub-Hex Mechanical Layer Phase 2a) as before. A unit
## routed through a gate should visibly walk through the gate rather than
## crossing its own defensive line at whatever point the portal happens to
## sit at.
func _crossing_offset(from_coord: Vector2i, to_coord: Vector2i) -> Vector2:
	if _wall_manager:
		var gate_offset: Variant = _wall_manager.get_gate_crossing_offset(from_coord, to_coord)
		if gate_offset != null:
			return gate_offset
	return _portal_offset_for_step(from_coord, to_coord)

func _portal_offset_for_step(from_coord: Vector2i, to_coord: Vector2i) -> Vector2:
	if not _hex_grid_map:
		return Vector2.ZERO
	return SubHexPortalGraph.portal_offset_for_step(_hex_grid_map, from_coord, to_coord)

## Terrain (current hex) and logistics (this edge) speed multipliers
## stacked onto MovementStepper.BASE_MOVE_SPEED — the same table the
## Strategic route was chosen against, plus the Day movement bonus,
## stacking multiplicatively with terrain/logistics like every other factor
## here. No Night case — see DAY_MOVE_SPEED_MULTIPLIER's own doc comment.
## `instance.definition.move_speed_multiplier` (mounted SPECIAL units run
## faster) stacks on top the same way; 1.0 for every non-mounted unit, so
## this is a no-op for most of the roster.
func _movement_speed(instance: UnitInstance, from_coord: Vector2i, to_coord: Vector2i) -> float:
	var speed := MovementStepper.BASE_MOVE_SPEED * UnitUpgrades.move_speed_multiplier(_tech_manager, instance.definition)
	var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	var multiplier := HexPathfinder.get_local_terrain_speed(_hex_grid_map, world)
	if _logistics_network:
		for neighbor in HexCoord.neighbors(instance.hex_coord):
			var segment := _logistics_network.get_segment_between(instance.hex_coord, neighbor)
			if segment and not segment.is_severed:
				var nearest := Geometry2D.get_closest_point_to_segment(world, HexCoord.axial_to_world(instance.hex_coord), HexCoord.axial_to_world(neighbor))
				if world.distance_to(nearest) <= HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS * 2.0:
					multiplier = maxf(multiplier, SupplyLineCatalog.get_speed_multiplier(segment.line_type, segment.tier))
	speed *= multiplier
	if TimeCycleManager.is_day():
		speed *= DAY_MOVE_SPEED_MULTIPLIER
	return speed

## --- Healing -----------------------------------------------------------

func _regen_if_friendly(instance: UnitInstance) -> void:
	if not instance.definition or instance.current_hp >= instance.definition.max_hp:
		return
	if not _is_friendly_hex(instance.hex_coord):
		return
	instance.current_hp = minf(instance.current_hp + instance.definition.max_hp * GARRISON_REGEN_FRACTION_PER_TICK, instance.definition.max_hp)

## "Friendly-controlled hex": carrying Military OR Civilian Zone of Control
## coverage, the same "secured ground" signal every other friendly-territory
## check in this project reads. No live logistics_network_path reference
## means no way to confirm friendly ground, so this conservatively
## withholds healing rather than assuming every hex is safe.
func _is_friendly_hex(coord: Vector2i) -> bool:
	if not _logistics_network:
		return false
	var zoc := _logistics_network.get_zoc_state(coord)
	return zoc.has_military_coverage() or zoc.has_civilian_coverage

func issue_wall_move_order(instance: UnitInstance, segment: WallSegment, world: Vector2, patrol: bool = false) -> bool:
	if not segment or segment.is_breached() or not instance.is_squad_rendered():
		return false
	var entry := Geometry2D.get_closest_point_to_segment(world, segment.point_a, segment.point_b)
	var was_on_wall := instance.on_wall
	var standing := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	var wall_path := WallWalkRoute.path_on_wall(_wall_manager, standing, entry) if was_on_wall else PackedVector2Array()
	issue_move_order(instance, HexCoord.world_to_axial(entry), entry - HexCoord.axial_to_world(HexCoord.world_to_axial(entry)))
	instance.wall_target = entry
	instance.wall_target_active = true
	instance.wall_route_loops = patrol
	if was_on_wall and not wall_path.is_empty():
		instance.on_wall = true
		instance.wall_patrol_route = wall_path
	if patrol:
		instance.wall_patrol_route = WallWalkRoute.perimeter(_wall_manager, segment, entry)
	return true

func _advance_wall_order(instance: UnitInstance, delta: float) -> void:
	var target: Vector2 = instance.wall_target
	var segment := WallWalkRoute.segment_at(_wall_manager, target)
	if not segment:
		instance.on_wall = false
		issue_hold_order(instance)
		move_order_unreachable.emit(instance, instance.hex_coord)
		return
	var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	if not instance.on_wall:
		_advance_toward(instance, HexCoord.world_to_axial(target), target - HexCoord.axial_to_world(HexCoord.world_to_axial(target)), false, delta)
		world = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		if world.distance_to(target) > 0.01:
			return
		instance.on_wall = true
		return # The approach already consumed this frame's movement budget.
	if instance.wall_patrol_route.is_empty():
		instance.wall_target_active = false
		instance.order = GameEnums.UnitOrderType.HOLD
		unit_order_issued.emit(instance, instance.order)
		return
	var route: PackedVector2Array = instance.wall_patrol_route
	if route.is_empty():
		return
	instance.order = GameEnums.UnitOrderType.PATROL if instance.wall_route_loops else GameEnums.UnitOrderType.MOVE
	var destination := route[0]
	# Every step must still lie on an intact wall; a breach stops the patrol.
	var next := world.move_toward(destination, _movement_speed(instance, instance.hex_coord, instance.hex_coord) * delta)
	var intact := true
	var checks := maxi(1, ceili(world.distance_to(next)))
	for i in range(1, checks + 1):
		if not WallWalkRoute.segment_at(_wall_manager, world.lerp(next, float(i) / checks)):
			intact = false
			break
	if not intact:
		instance.on_wall = false
		issue_hold_order(instance)
		return
	_set_world_position(instance, next)
	instance.wall_target = destination
	if next.distance_to(destination) <= 0.01:
		route.remove_at(0)
		if instance.wall_route_loops:
			route.append(destination)
		instance.wall_patrol_route = route

func _clear_cached_route(instance: UnitInstance) -> void:
	_local_routes.erase(instance.id)
	_route_targets.erase(instance.id)
	_route_revisions.erase(instance.id)
	_replan_backoff.erase(instance.id)
	_unreachable_reported.erase(instance.id)
