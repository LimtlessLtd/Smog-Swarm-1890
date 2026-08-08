class_name UnitOrderController
extends Node

## Design doc Phase 5.6: "the actual automation the pitch promises" — the
## standard RTS order set (move, attack-move, hold, patrol) plus garrison,
## driving UnitManager's trained units around the map. Mirrors
## HordeManager's own movement shape almost exactly (a periodic replan via
## Phase 5.5's HexPathfinder, continuous travel between hexes via
## MovementStepper) — the same sibling relationship to HexPathfinder that
## class already has, just player-directed instead of autonomous drift.
##
## **Real-time continuous movement (user request, this pass) replaces the
## old hex-stepping model** — a unit used to snap instantly from one hex to
## the next once every `MOVE_INTERVAL_SECONDS`; it now walks smoothly
## (`MovementStepper.advance_toward_hex()`, world-units/second, terrain- and
## logistics-scaled) toward the next hex's center every `_process()` frame,
## steering around static obstacles (props/buildings) the same way
## `HordeManager` does — see that class's own doc comment for the shared
## design, and `MovementStepper.gd` for the actual stepping/steering math.
## `HexPathfinder` still supplies the STRATEGIC route (which hexes to
## cross, respecting terrain/logistics costs) — unchanged; only how an
## entity gets from one hex center to the next changed. Units are still
## never blocked by walls (only `HordeManager`'s hordes are, today) —
## pre-existing asymmetry, not touched by this pass.
##
## `LOGIC_TICK_SECONDS` (renamed from the old `MOVE_INTERVAL_SECONDS` — it
## no longer gates movement, only the one periodic side-effect below) still
## drives `_regen_if_friendly()` at the same real-world rate as before.
##
## Deliberately holds no reference to CombatEngine, HordeManager, or
## CombatCoordinator, and never calls any of them: a unit arriving on a
## horde's hex doesn't trigger a fight HERE. That job belongs to the new
## CombatCoordinator (Phase 5.4/5.9/5.10's live combat trigger), which
## listens to this class's own `unit_moved` signal (fired once per hex
## boundary actually crossed, not just final arrival) from the outside —
## same "owns neither" layering FogOfWarManager already uses over
## BuildingManager. ATTACK_MOVE is still tracked as data-distinct from
## MOVE, but turns out to need no distinct behavior anywhere:
## CombatCoordinator engages on contact regardless of a unit's current
## order (see its own doc comment, "contact matters however it happens"),
## so an attack-moving unit and a merely-passing-through one fight
## identically the moment either touches a horde's hex. Garrison orders'
## "stationary defense bonus" is real now too, though not computed here —
## CombatCoordinator._garrison_incoming_multiplier() reads
## UnitInstance.order directly at engagement time, the same "owns neither,
## only reads the shared data" split this file already keeps from combat.
##
## UnitManager and UnitOrderController never reference each other's
## methods, only the UnitInstance data both read/write (order/move_target/
## patrol_waypoints/path) — same "owns neither, only computes from what's
## passed in" split CombatEngine/UnitManager already keep from each other.
##
## Phase 2.5.4, decided: "healing/replenishment is Garrison-gated" — the
## project's first regen mechanic of any kind, finally giving
## issue_garrison_order() an actual payoff over plain HOLD-with-no-benefit.
## A damaged unit under HOLD or GARRISON heals a fraction of its max_hp back
## each LOGIC_TICK_SECONDS tick, but ONLY while standing on a hex carrying
## Military or Civilian Zone of Control coverage (`_is_friendly_hex()`,
## reusing the already-optional `logistics_network_path` this class was
## wired with for HexPathfinder's road/rail/canal discount, Phase 5.5 — no
## new export needed). Regrowing a squad's own derived headcount (Phase
## 2.5.4's UnitInstance.get_squad_headcount()) needs no extra code here:
## it's already computed live from current_hp everywhere it's read.

signal unit_order_issued(instance: UnitInstance, order: GameEnums.UnitOrderType)
signal unit_arrived(instance: UnitInstance, coord: Vector2i)
signal unit_moved(instance: UnitInstance, from_coord: Vector2i, to_coord: Vector2i)

@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — HexPathfinder's road/rail/canal discount (now a continuous SPEED bonus, not just a path-preference one — see MovementStepper), AND (Phase 2.5.4) the Zone of Control read _is_friendly_hex() gates Garrison/Hold healing on. Unset skips both gracefully.
@export var building_manager_path: NodePath  ## Optional — local obstacle avoidance (user request): buildings steer continuous movement around them regardless of Tactical hydration. Unset just means no building avoidance.
@export var local_detail_manager_path: NodePath  ## Optional — local obstacle avoidance: props (trees/rocks/etc.) only exist as live data while their hex is Tactical-hydrated (LocalDetailManager.get_props_at()) — unset (or a currently-dehydrated hex) just means no prop avoidance there.

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _local_detail_manager: LocalDetailManager
var _logic_tick_timer: float = 0.0

## Balancing number, not an architecture one — same framing as
## HordeManager.LOGIC_TICK_SECONDS, which this deliberately matches (both
## used to gate a hex-step at this same rate; now both just gate their own
## remaining periodic side-effect at it). No longer governs movement itself
## — see this class's own doc comment.
const LOGIC_TICK_SECONDS: float = 20.0

## Rough clearance radius a moving unit/squad presents to
## MovementStepper.steer_around_obstacles() — approximates a squad's own
## visual spread (TacticalEntityLayer.FIGURE_SPREAD) rather than a single
## figure, so steering reacts before the near edge of the formation would
## actually clip an obstacle. Placeholder balancing number, not an
## architecture decision, same framing as ObstacleRadii's own table.
const ENTITY_RADIUS: float = 20.0

## Design doc Phase 5.1's Day Phase bullet: "Military units get increased
## movement speed and damage" — the movement-speed half, unblocked now that
## movement is continuous (Phase 5.5) rather than a fixed per-hex timer.
## No exact number in the design doc — a placeholder balancing multiplier,
## same disclaimer every other constant table in this project already
## carries. Deliberately no Night-time penalty — the doc only ever frames
## this as a Day bonus, not a Night debuff, so Night is plain baseline
## speed (`1.0`, i.e. this constant simply doesn't apply). The damage half
## of the same bullet lives in CombatCoordinator.DAY_DAMAGE_MULTIPLIER
## instead — this class has no combat code of its own to fold it into.
const DAY_MOVE_SPEED_MULTIPLIER: float = 1.2

## Phase 2.5.4's first-ever regen mechanic — a fraction of max_hp (not a
## flat number) so a Tier 5 unit's much larger HP pool doesn't heal
## proportionally slower than a Tier 0 unit's. Placeholder balancing
## number, not an architecture decision, same framing as every other
## constant table in this project; ticks on LOGIC_TICK_SECONDS, applied
## only to HOLD/GARRISON units (a moving/patrolling unit never reaches it).
const GARRISON_REGEN_FRACTION_PER_TICK: float = 0.05

func _ready() -> void:
	# Same reasoning as every other tick-driven manager (TickManager,
	# TimeCycleManager, HordeManager): background-simulation infrastructure
	# that shouldn't freeze if a future system ever pauses the SceneTree.
	process_mode = Node.PROCESS_MODE_ALWAYS
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

func _process(delta: float) -> void:
	if not _unit_manager:
		return
	var units := _unit_manager.get_all_units()

	# Continuous movement — every frame, every unit under an order that
	# actually moves (MOVE/ATTACK_MOVE/PATROL); a no-op for HOLD/GARRISON.
	for instance in units:
		_advance_unit(instance, delta)

	# The one remaining periodic side-effect (Garrison/Hold regen) —
	# unchanged real-world cadence from the old movement-tick rate.
	_logic_tick_timer += delta
	while _logic_tick_timer >= LOGIC_TICK_SECONDS:
		_logic_tick_timer -= LOGIC_TICK_SECONDS
		for instance in units:
			if instance.order == GameEnums.UnitOrderType.HOLD or instance.order == GameEnums.UnitOrderType.GARRISON:
				_regen_if_friendly(instance)

## --- Order issuing (player-facing API — called by UnitCommandController, Phase 6.1) --

func issue_move_order(instance: UnitInstance, destination: Vector2i) -> void:
	_set_order(instance, GameEnums.UnitOrderType.MOVE)
	instance.move_target = destination
	instance.path.clear()

func issue_attack_move_order(instance: UnitInstance, destination: Vector2i) -> void:
	_set_order(instance, GameEnums.UnitOrderType.ATTACK_MOVE)
	instance.move_target = destination
	instance.path.clear()

func issue_hold_order(instance: UnitInstance) -> void:
	_set_order(instance, GameEnums.UnitOrderType.HOLD)
	instance.path.clear()

## Stationary at the unit's own current hex — "assign a unit to a
## building/wall segment for a stationary defense bonus instead of
## patrolling" (design doc). The bonus itself isn't computed anywhere yet;
## see this class's own doc comment for why.
func issue_garrison_order(instance: UnitInstance) -> void:
	_set_order(instance, GameEnums.UnitOrderType.GARRISON)
	instance.path.clear()

## `waypoints` must be non-empty — a no-op (reported via return value) if
## it isn't, rather than silently accepting a PATROL order with nothing to
## loop through.
func issue_patrol_order(instance: UnitInstance, waypoints: Array[Vector2i]) -> bool:
	if waypoints.is_empty():
		return false
	_set_order(instance, GameEnums.UnitOrderType.PATROL)
	instance.patrol_waypoints = waypoints.duplicate()
	instance.patrol_target_index = 0
	instance.path.clear()
	return true

func _set_order(instance: UnitInstance, order: GameEnums.UnitOrderType) -> void:
	instance.order = order
	unit_order_issued.emit(instance, order)

## --- Continuous movement ----------------------------------------------------

func _advance_unit(instance: UnitInstance, delta: float) -> void:
	match instance.order:
		GameEnums.UnitOrderType.MOVE, GameEnums.UnitOrderType.ATTACK_MOVE:
			_advance_toward(instance, instance.move_target, true, delta)
		GameEnums.UnitOrderType.PATROL:
			_advance_patrol(instance, delta)
		_:
			pass  ## HOLD/GARRISON: stationary — regen is handled by the periodic logic tick in _process(), not every frame.

## `revert_to_hold_on_arrival`: true for MOVE/ATTACK_MOVE (a one-shot order
## that's "done" once the destination is reached — design doc: "then
## reverts to HOLD on arrival"), false for PATROL (arriving just advances to
## the next leg, handled by _advance_patrol() itself rather than here).
##
## Walks `instance` continuously toward `destination`, consuming up to
## `delta` seconds of travel this call — MovementStepper.advance_toward_hex()
## handles one hex-segment at a time; this loop threads through however many
## hex boundaries `delta` covers (more than one is possible at very high
## TickManager speeds), emitting unit_moved once per boundary actually
## crossed, in order — see this class's own doc comment on why that
## per-crossing signal contract matters to CombatCoordinator/
## StrategicOverlayManager/etc.
func _advance_toward(instance: UnitInstance, destination: Vector2i, revert_to_hold_on_arrival: bool, delta: float) -> void:
	if instance.hex_coord == destination:
		if revert_to_hold_on_arrival:
			_set_order(instance, GameEnums.UnitOrderType.HOLD)
		return
	if instance.path.is_empty():
		_replan(instance, destination)
	if instance.path.is_empty():
		return  ## No route found this cycle (e.g. destination currently unreachable) — try again next frame.

	var remaining := delta
	while remaining > 0.0 and not instance.path.is_empty():
		var next_coord: Vector2i = instance.path[0]
		var from_coord := instance.hex_coord  ## Captured BEFORE the call below overwrites it — this is the hex actually being left this crossing.
		var speed := _movement_speed(from_coord, next_coord)
		var obstacles := _gather_obstacles(from_coord, next_coord)
		var result := MovementStepper.advance_toward_hex(from_coord, instance.local_position, next_coord, remaining, speed, obstacles, ENTITY_RADIUS)
		instance.hex_coord = result["hex_coord"]
		instance.local_position = result["local_position"]
		remaining -= float(result["seconds_used"])
		if not result["arrived"]:
			break  ## Used this frame's whole remaining budget without finishing the crossing.

		instance.path.pop_front()
		unit_moved.emit(instance, from_coord, instance.hex_coord)
		if instance.hex_coord == destination:
			unit_arrived.emit(instance, instance.hex_coord)
			if revert_to_hold_on_arrival:
				_set_order(instance, GameEnums.UnitOrderType.HOLD)

func _advance_patrol(instance: UnitInstance, delta: float) -> void:
	if not instance.has_patrol_waypoints():
		return
	instance.patrol_target_index = wrapi(instance.patrol_target_index, 0, instance.patrol_waypoints.size())
	var target: Vector2i = instance.patrol_waypoints[instance.patrol_target_index]
	if instance.hex_coord == target:
		instance.patrol_target_index = wrapi(instance.patrol_target_index + 1, 0, instance.patrol_waypoints.size())
		return
	_advance_toward(instance, target, false, delta)

func _replan(instance: UnitInstance, destination: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var path := HexPathfinder.find_path(_hex_grid_map, instance.hex_coord, destination, _logistics_network)
	if path.size() > 1:
		path.remove_at(0)  # path[0] is the unit's own current hex.
		instance.path = path

## Terrain (current hex) and logistics (this specific edge) speed
## multipliers stacked onto MovementStepper.BASE_MOVE_SPEED — same
## HexPathfinder table the Strategic route itself was chosen against, now
## also shaping how fast continuous movement crosses it (Phase 2.12.1) —
## plus Phase 5.1's Day movement bonus, stacking multiplicatively with
## terrain/logistics like every other factor here rather than replacing
## them. No Night case — see DAY_MOVE_SPEED_MULTIPLIER's own doc comment.
func _movement_speed(from_coord: Vector2i, to_coord: Vector2i) -> float:
	var speed := MovementStepper.BASE_MOVE_SPEED
	if _hex_grid_map:
		speed *= HexPathfinder.get_terrain_speed_multiplier(_hex_grid_map.get_cell(from_coord))
	speed *= HexPathfinder.get_logistics_speed_multiplier(_logistics_network, from_coord, to_coord)
	if TimeCycleManager.is_day():
		speed *= DAY_MOVE_SPEED_MULTIPLIER
	return speed

## Buildings (always queryable) + props (only where Tactical-hydrated) near
## both the hex a unit currently occupies and the one it's walking toward —
## see this class's own doc comment and ObstacleRadii for why these two
## sources are treated differently.
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

## --- Healing (Phase 2.5.4) -------------------------------------------------

func _regen_if_friendly(instance: UnitInstance) -> void:
	if not instance.definition or instance.current_hp >= instance.definition.max_hp:
		return
	if not _is_friendly_hex(instance.hex_coord):
		return
	instance.current_hp = minf(instance.current_hp + instance.definition.max_hp * GARRISON_REGEN_FRACTION_PER_TICK, instance.definition.max_hp)

## "Friendly-controlled hex" — decided: carrying Military OR Civilian Zone
## of Control coverage (LogisticsNetwork, Phase 2.3), the same "secured
## ground" signal every other friendly-territory check in this project
## already reads. No live logistics_network_path reference means no way to
## confirm friendly ground, so this conservatively withholds healing rather
## than assuming every hex is safe.
func _is_friendly_hex(coord: Vector2i) -> bool:
	if not _logistics_network:
		return false
	var zoc := _logistics_network.get_zoc_state(coord)
	return zoc.has_military_coverage() or zoc.has_civilian_coverage
