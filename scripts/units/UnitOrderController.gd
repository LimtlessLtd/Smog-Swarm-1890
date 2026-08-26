class_name UnitOrderController
extends Node

## The standard RTS order set (move, attack-move, hold, patrol) plus
## garrison, driving UnitManager's trained units around the map. Mirrors
## HordeManager's own movement shape almost exactly (a periodic replan via
## HexPathfinder, continuous travel between hexes via MovementStepper) — the
## same sibling relationship to HexPathfinder that class has, just
## player-directed instead of autonomous drift.
##
## Movement is continuous (MovementStepper.advance_toward_hex(), world-
## units/second, terrain- and logistics-scaled), walking smoothly every
## _process() frame, steering around static obstacles (props/buildings) the
## same way HordeManager does. HexPathfinder still supplies the STRATEGIC
## route (which hexes to cross, respecting terrain/logistics costs); each
## crossing's actual aim point is the real sub-hex portal
## SubHexPortalGraph.portal_offset_for_step() resolves for that hex pair
## (Sub-Hex Mechanical Layer Phase 2a, todo.md,
## [[sub-hex-mechanical-layer-epic]] memory) rather than the hex's plain
## geometric center, falling back to the center only when no portal exists
## for that edge. Solid wall blocks a unit's route (HexPathfinder.find_path()'s
## own wall_manager argument excludes those edges, and _blocked_by_wall()
## re-checks each crossing live); a Gate does not — that asymmetry is what
## gives gates a purpose on the player's side, and it is the only movement
## difference between the two. See WallManager.get_blocking_segment().
##
## LOGIC_TICK_SECONDS no longer gates movement — it only drives
## _regen_if_friendly() at a fixed real-world rate.
##
## Holds no reference to CombatEngine, HordeManager, or CombatCoordinator,
## and never calls any of them: a unit arriving on a horde's hex doesn't
## trigger a fight HERE. That's CombatCoordinator's job, which listens to
## this class's own unit_moved signal (fired once per hex boundary actually
## crossed, not just final arrival) from the outside — same "owns neither"
## layering FogOfWarManager uses over BuildingManager. ATTACK_MOVE is
## tracked as data-distinct from MOVE but needs no distinct behavior
## anywhere: CombatCoordinator engages on contact regardless of a unit's
## current order, so an attack-moving unit and a merely-passing-through one
## fight identically the moment either touches a horde's hex. Garrison's
## "stationary defense bonus" is computed by CombatCoordinator reading
## UnitInstance.order directly at engagement time, not here.
##
## UnitManager and UnitOrderController never reference each other's
## methods, only the UnitInstance data both read/write (order/move_target/
## patrol_waypoints/path) — same "owns neither, only computes from what's
## passed in" split CombatEngine/UnitManager keep from each other.
##
## Healing/replenishment is Garrison-gated. A damaged unit under HOLD or
## GARRISON heals a fraction of its max_hp back each LOGIC_TICK_SECONDS
## tick, but only while standing on a hex carrying Military or Civilian Zone
## of Control coverage (_is_friendly_hex(), reusing the already-optional
## logistics_network_path this class is wired with for HexPathfinder's
## road/rail/canal discount). Regrowing a squad's own derived headcount
## needs no extra code here — it's already computed live from current_hp
## everywhere it's read.

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
@export var local_detail_manager_path: NodePath  ## Optional — local obstacle avoidance: props (trees/rocks/etc.) only exist as live data while their hex is Tactical-hydrated (LocalDetailManager.get_props_at()).
@export var tech_manager_path: NodePath  ## Optional — the SPECIAL-role movement upgrade (UnitUpgrades.move_speed_multiplier()). Unset means units move at their raw UnitDefinition speed.
@export var wall_manager_path: NodePath  ## Optional — strategic route wall-avoidance, fed into HexPathfinder.find_path() so a unit's route goes around an un-breached wall. Unset means no wall-awareness.

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _local_detail_manager: LocalDetailManager
var _tech_manager: TechManager
var _wall_manager: WallManager
var _logic_tick_timer: float = 0.0

const LOGIC_TICK_SECONDS: float = 20.0  ## Matches HordeManager.LOGIC_TICK_SECONDS. No longer governs movement itself.

const ENTITY_RADIUS: float = 20.0  ## Clearance radius a moving unit/squad presents to MovementStepper.steer_around_obstacles() — approximates a squad's visual spread (TacticalEntityLayer.FIGURE_SPREAD) rather than a single figure.

## Local steering is a cheap, memoryless nudge — MovementStepper's own doc
## comment already notes it's not guaranteed to escape a dense obstacle
## cluster. Past STUCK_UNSTICK_SECONDS of near-zero net progress, the unit
## bypasses obstacle steering entirely (a direct beeline, briefly clipping
## through whatever it was stuck on) rather than oscillating forever — a
## pragmatic escape hatch, not a real local pathfinding search. Walls are
## avoided at the STRATEGIC route level instead (HexPathfinder.find_path()'s
## wall_manager param), so this fallback mainly matters for local-only
## obstacles the route can't route around, since a hex is much bigger than a
## single building's footprint.
##
## Measured, not assumed: WOODLAND is dense enough that this matters for a
## whole biome, not just unlucky prop placement. ENTITY_RADIUS (20) +
## ObstacleRadii.PROP_RADIUS[TREE] (24) = 44 wu of required clearance, against
## TerrainDetailScatter's own WOODLAND density comment ("~21-unit gap: canopy,
## trees touching" between 20-unit-diameter trees, i.e. ~41 wu of mean
## tree-CENTER spacing) — the entity's clearance requirement is LARGER than
## the average gap between trees in the game's densest biome, confirmed with
## a synthetic corridor test (scripts/test/verify_woodland_steering.gd) at
## realistic WOODLAND density: plain steering never escapes (still 21+ wu
## short after 235 simulated seconds, a leg that should take ~20s clear).
##
## The bypass used to be re-decided fresh every _advance_toward() call from
## _is_stuck() alone, which reset the instant one frame's progress exceeded
## STUCK_PROGRESS_FRACTION of expected — exactly what a single bypassed
## frame produces. The same test with that logic still never got through:
## 153 stuck/bypass/re-stuck cycles over 600 simulated seconds, flip-flopping
## at the edge of the cluster instead of clearing it, because obstacle
## avoidance re-engaged and shoved the unit right back in on the very next
## frame. _bypassing_obstacles below fixes this by staying sticky: once
## triggered, bypass stays on until the unit's current position no longer
## overlaps ANY nearby obstacle's clearance circle, not just until one frame
## looked like progress. Same test, same corridor: one bypass activation,
## clear in 23s.
const STUCK_UNSTICK_SECONDS: float = 3.0

## Hard bound on how many times one _advance_toward() call may clear its
## path and re-plan after finding a wall across the next crossing. The route
## and the crossing check are deliberately asked the identical question
## (_blocked_by_wall()), so a re-plan cannot hand back the same refused edge
## and this should never fire — it exists so that if some future change lets
## them disagree again, the symptom is a unit that pauses rather than a
## frame that never ends.
const MAX_REPLANS_PER_CALL: int = 4
const STUCK_PROGRESS_FRACTION: float = 0.25  ## Below this fraction of the speed-implied distance, a crossing attempt counts as "not really progressing".

## Transient (never saved) — unit id -> seconds of near-zero net progress
## while under a moving order. Reset to 0 the instant real progress
## resumes, or the unit stops moving for any reason (order change,
## HOLD/GARRISON, arrival).
var _stuck_seconds: Dictionary = {}

## Transient (never saved) — unit id -> true while that unit is in the
## sticky obstacle-bypass state _effective_obstacles() manages. See
## STUCK_UNSTICK_SECONDS's own doc comment for why this has to be sticky
## (persist across calls until genuinely clear) rather than re-derived from
## _is_stuck() every frame.
var _bypassing_obstacles: Dictionary = {}

## A failed A* search costs a full frontier exhaustion over every reachable
## hex — the most expensive search the map can produce, since it only
## returns after running out of frontier. Retrying it every frame for a unit
## ordered somewhere genuinely unreachable burned that cost ~60x/second per
## unit, forever. Backing off is safe: the only things that can turn an
## unreachable goal reachable are a wall breached/demolished or a marsh
## drained, none of which happen within a frame of each other.
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
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if local_detail_manager_path != NodePath():
		_local_detail_manager = get_node(local_detail_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)

func _process(delta: float) -> void:
	if not _unit_manager:
		return
	var units := _unit_manager.get_all_units()

	# Continuous movement — every frame, every unit under an order that
	# actually moves (MOVE/ATTACK_MOVE/PATROL); a no-op for HOLD/GARRISON.
	for instance in units:
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
	instance.pending_garrison_arrival = false  ## A fresh player order always overrides an in-flight "route to garrison" — see that field's own doc comment.
	_set_order(instance, GameEnums.UnitOrderType.MOVE)
	instance.move_target = destination
	instance.move_target_local = destination_local
	instance.path.clear()

func issue_attack_move_order(instance: UnitInstance, destination: Vector2i, destination_local: Vector2 = Vector2.ZERO) -> void:
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
	_replan_backoff.erase(instance.id)
	_unreachable_reported.erase(instance.id)
	_bypassing_obstacles.erase(instance.id)
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
	match instance.order:
		GameEnums.UnitOrderType.MOVE, GameEnums.UnitOrderType.ATTACK_MOVE:
			_advance_toward(instance, instance.move_target, instance.move_target_local, true, delta)
		GameEnums.UnitOrderType.PATROL:
			_advance_patrol(instance, delta)
		_:
			## HOLD/GARRISON: stationary — regen is handled by the periodic
			## logic tick in _process(), not every frame. Also drops
			## stuck-tracking state — a unit stopped on purpose shouldn't
			## carry a stale "was stuck" timer into its next order.
			_stuck_seconds.erase(instance.id)
			_bypassing_obstacles.erase(instance.id)

## `revert_to_hold_on_arrival`: true for MOVE/ATTACK_MOVE (a one-shot order
## that's "done" once the destination is reached), false for PATROL
## (arriving just advances to the next leg, handled by _advance_patrol()).
##
## `destination_local` — the offset within `destination`'s own hex the unit
## should end up at, ZERO for "just the hex center". Only applied on the
## FINAL leg of the path (the `next_coord == destination` check below) —
## every hex merely passed through en route still routes through its own
## plain center.
##
## Walks `instance` continuously toward `destination`, consuming up to
## `delta` seconds of travel this call — MovementStepper.advance_toward_hex()
## handles one hex-segment at a time; this loop threads through however many
## hex boundaries `delta` covers (more than one is possible at high
## TickManager speeds), emitting unit_moved once per boundary actually
## crossed, in order — CombatCoordinator/StrategicOverlayManager depend on
## that per-crossing contract.
func _advance_toward(instance: UnitInstance, destination: Vector2i, destination_local: Vector2, revert_to_hold_on_arrival: bool, delta: float) -> void:
	# Already on the destination hex — a direct sub-hex walk toward
	# destination_local via the same MovementStepper math every other leg
	# uses, deliberately NOT routed through instance.path/_replan():
	# HexPathfinder.find_path() returns a trivial single-hex path for
	# start == goal that _replan() discards (path.size() > 1 check), so
	# going through that path would leave the unit permanently stuck.
	if instance.hex_coord == destination:
		var before := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		var obstacles := _effective_obstacles(instance, before, _gather_obstacles(instance.hex_coord, destination))
		var speed := _movement_speed(instance, instance.hex_coord, destination)
		var result := MovementStepper.advance_toward_hex(instance.hex_coord, instance.local_position, destination, delta, speed, obstacles, ENTITY_RADIUS, float(instance.id), destination_local)
		instance.local_position = result["local_position"]
		_update_stuck(instance, before, HexCoord.axial_to_world(instance.hex_coord) + instance.local_position, HexCoord.axial_to_world(destination) + destination_local, speed, delta)
		if result["arrived"]:
			unit_arrived.emit(instance, instance.hex_coord)
			if revert_to_hold_on_arrival:
				_revert_on_arrival(instance)
		return
	if instance.path.is_empty():
		_replan_with_backoff(instance, destination, delta)
	if instance.path.is_empty():
		return  ## No route right now — _replan_with_backoff() owns the retry cadence and the one-shot player-facing report.

	var world_pos_before := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	var last_speed := 1.0
	## The point this frame's LAST crossing attempt was actually aiming at, and
	## whether any crossing completed. _update_stuck() measures progress toward
	## the current leg rather than toward `destination`: a route legitimately
	## walks AWAY from the destination in a straight line whenever it detours
	## around water or impassable ground, which a destination-relative measure
	## would read as being stuck. A completed crossing is unambiguous progress
	## and clears the timer outright — it also moves the aim point, so the
	## before/after distances either side of it aren't comparable.
	var leg_target := world_pos_before
	var crossed_a_boundary := false
	var replans_this_call := 0
	var remaining := delta
	while remaining > 0.0 and not instance.path.is_empty():
		var next_coord: Vector2i = instance.path[0]
		var from_coord := instance.hex_coord  ## Captured BEFORE the call below overwrites it — this is the hex actually being left this crossing.
		var leg_local_offset := destination_local if next_coord == destination else _crossing_offset(from_coord, next_coord)

		# Live wall re-check — _replan() above only avoids walls that
		# existed at planning time; a wall built mid-route (or restored
		# from a save) could leave a stale instance.path still pointing
		# through an edge that's blocked NOW. Same "peek every hex-crossing
		# attempt" cadence HordeManager uses before deciding to siege —
		# units get a fresh route around it instead. to_world includes
		# leg_local_offset so this checks the SAME line the unit is about
		# to actually walk (the real portal crossing point), not the plain
		# hex center a wall near the boundary could otherwise miss.
		if _wall_manager and _blocked_by_wall(from_coord, next_coord):
			instance.path.clear()
			_replan_with_backoff(instance, destination, remaining)
			if instance.path.is_empty():
				return  ## No route around the new wall right now — try again next frame.
			replans_this_call += 1
			if replans_this_call > MAX_REPLANS_PER_CALL:
				return  ## See MAX_REPLANS_PER_CALL — bail rather than spin.
			continue  ## Re-read path[0] fresh — it may not even be `next_coord` any more.

		var speed := _movement_speed(instance, from_coord, next_coord)
		last_speed = speed
		leg_target = HexCoord.axial_to_world(next_coord) + leg_local_offset
		var world_pos := HexCoord.axial_to_world(from_coord) + instance.local_position
		var obstacles := _effective_obstacles(instance, world_pos, _gather_obstacles(from_coord, next_coord))
		var result := MovementStepper.advance_toward_hex(from_coord, instance.local_position, next_coord, remaining, speed, obstacles, ENTITY_RADIUS, float(instance.id), leg_local_offset)
		instance.hex_coord = result["hex_coord"]
		instance.local_position = result["local_position"]
		remaining -= float(result["seconds_used"])
		if not result["arrived"]:
			break  ## Used this frame's whole remaining budget without finishing the crossing.

		instance.path.pop_front()
		crossed_a_boundary = true
		unit_moved.emit(instance, from_coord, instance.hex_coord)
		if instance.hex_coord == destination:
			unit_arrived.emit(instance, instance.hex_coord)
			if revert_to_hold_on_arrival:
				_revert_on_arrival(instance)
	var world_pos_after := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	if crossed_a_boundary:
		_stuck_seconds[instance.id] = 0.0
	else:
		_update_stuck(instance, world_pos_before, world_pos_after, leg_target, last_speed, delta)

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
		if instance.hex_coord != target:
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
## Asks about the CENTRE-TO-CENTRE line, byte-for-byte the same question
## HexPathfinder.find_path() asks when it decides whether that edge exists at
## all — including the same `gates_are_passable`. It used to test the line
## the unit was really about to walk (centre to the leg's own sub-hex portal
## offset), on the reasoning that this catches a wall sitting near the
## boundary. It also let the two disagree, and disagreement here is not a
## missed wall, it is a live-lock: the route keeps returning an edge the
## crossing check keeps refusing, so the unit clears and re-plans the same
## path forever without moving. MAX_REPLANS_PER_CALL is the backstop for any
## future version of that; this is the fix.
func _blocked_by_wall(from_coord: Vector2i, to_coord: Vector2i) -> bool:
	return _wall_manager.get_blocking_segment(from_coord, to_coord, HexCoord.axial_to_world(from_coord), HexCoord.axial_to_world(to_coord), true) != null

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
	speed *= HexPathfinder.get_movement_speed_multiplier(_hex_grid_map, _logistics_network, from_coord, to_coord)
	if TimeCycleManager.is_day():
		speed *= DAY_MOVE_SPEED_MULTIPLIER
	return speed

func _is_stuck(instance: UnitInstance) -> bool:
	return _stuck_seconds.get(instance.id, 0.0) >= STUCK_UNSTICK_SECONDS

## `speed` is whatever the caller was using for this crossing attempt (the
## expected distance-per-second if nothing were in the way) — comparing
## against that speed-implied distance, rather than a flat world-units
## constant, keeps this correct across every terrain/logistics/day speed
## multiplier already stacked into `speed`.
##
## Measures how much CLOSER TO `leg_target` the unit got, not how far it
## moved. Raw displacement counts a unit shaking left-right against an
## obstacle as full-speed travel, so the bypass this timer exists to trigger
## never fired and the unit vibrated indefinitely — "sometimes units get
## stuck during a move command, and they seem to vibrate from side to side
## incredibly fast" (user report). Net approach is zero for that motion no
## matter how fast it is, which is the property that actually distinguishes
## being stuck from moving.
func _update_stuck(instance: UnitInstance, before: Vector2, after: Vector2, leg_target: Vector2, speed: float, delta: float) -> void:
	if delta <= 0.0:
		return
	var approached := before.distance_to(leg_target) - after.distance_to(leg_target)
	var expected := maxf(speed, 0.01) * delta
	if approached < expected * STUCK_PROGRESS_FRACTION:
		_stuck_seconds[instance.id] = _stuck_seconds.get(instance.id, 0.0) + delta
	else:
		_stuck_seconds[instance.id] = 0.0

## Decides which obstacle list a crossing attempt actually steers against —
## the real, gathered `obstacles`, or an empty bypass — and owns
## _bypassing_obstacles' sticky lifecycle. See STUCK_UNSTICK_SECONDS's own
## doc comment for the measured reason this has to stay sticky rather than
## being re-derived from _is_stuck() every call: a single bypassed frame
## routinely looks like "progress" by STUCK_PROGRESS_FRACTION's own
## definition without actually clearing a dense cluster, which re-armed
## steering on the very next call and shoved the unit right back in.
func _effective_obstacles(instance: UnitInstance, world_pos: Vector2, obstacles: Array[Dictionary]) -> Array[Dictionary]:
	if _bypassing_obstacles.get(instance.id, false):
		if _obstacle_overlaps(world_pos, obstacles):
			return []
		_bypassing_obstacles.erase(instance.id)  ## Genuinely clear now -- resume real avoidance.
		return obstacles
	if _is_stuck(instance):
		_bypassing_obstacles[instance.id] = true
		return []
	return obstacles

## Whether `world_pos` currently sits inside any obstacle's own clearance
## circle (entity radius + that obstacle's radius) -- the same clearance
## test steer_around_obstacles() uses per-obstacle, just evaluated at the
## entity's actual position rather than along a lookahead line, since this
## is asking "are we still inside the cluster" rather than "is something in
## our path".
func _obstacle_overlaps(world_pos: Vector2, obstacles: Array[Dictionary]) -> bool:
	for obstacle in obstacles:
		var clearance: float = ENTITY_RADIUS + float(obstacle["radius"])
		if world_pos.distance_to(obstacle["position"]) < clearance:
			return true
	return false

## Buildings (always queryable) + props (only where Tactical-hydrated) near
## both the hex a unit currently occupies and the one it's walking toward.
func _gather_obstacles(coord: Vector2i, next_coord: Vector2i) -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []
	_add_hex_obstacles(coord, obstacles)
	if next_coord != coord:
		_add_hex_obstacles(next_coord, obstacles)
	return obstacles

func _add_hex_obstacles(coord: Vector2i, obstacles: Array[Dictionary]) -> void:
	var hex_center := HexCoord.axial_to_world(coord)
	if _building_manager:
		for building in _building_manager.get_buildings_at(coord):
			obstacles.append({"position": hex_center + building.local_position, "radius": ObstacleRadii.BUILDING_RADIUS})
	if _local_detail_manager:
		for prop in _local_detail_manager.get_props_at(coord):
			obstacles.append({"position": hex_center + prop.local_position, "radius": ObstacleRadii.for_prop(prop.prop_type)})

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
