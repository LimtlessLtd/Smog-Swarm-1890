class_name UnitOrderController
extends Node

## Design doc Phase 5.6: "the actual automation the pitch promises" — the
## standard RTS order set (move, attack-move, hold, patrol) plus garrison,
## driving UnitManager's trained units around the map. Mirrors
## HordeManager's own movement-tick shape almost exactly (a periodic replan
## via Phase 5.5's HexPathfinder, one hex step per interval) — the same
## sibling relationship to HexPathfinder that class already has, just
## player-directed instead of autonomous drift.
##
## Deliberately holds no reference to CombatEngine, HordeManager, or
## CombatCoordinator, and never calls any of them: a unit arriving on a
## horde's hex doesn't trigger a fight HERE. That job belongs to the new
## CombatCoordinator (Phase 5.4/5.9/5.10's live combat trigger), which
## listens to this class's own `unit_moved` signal (fired every step, not
## just final arrival) from the outside — same "owns neither" layering
## FogOfWarManager already uses over BuildingManager. ATTACK_MOVE is still
## tracked as data-distinct from MOVE, but turns out to need no distinct
## behavior anywhere: CombatCoordinator engages on contact regardless of a
## unit's current order (see its own doc comment, "contact matters however
## it happens"), so an attack-moving unit and a merely-passing-through one
## fight identically the moment either touches a horde's hex. Garrison
## orders' "stationary defense bonus" is real now too, though not computed
## here — CombatCoordinator._garrison_incoming_multiplier() reads
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
## each movement tick, but ONLY while standing on a hex carrying Military or
## Civilian Zone of Control coverage (`_is_friendly_hex()`, reusing the
## already-optional `logistics_network_path` this class was wired with for
## HexPathfinder's road/rail/canal discount, Phase 5.5 — no new export
## needed). Regrowing a squad's own derived headcount (Phase 2.5.4's
## UnitInstance.get_squad_headcount()) needs no extra code here: it's
## already computed live from current_hp everywhere it's read.

signal unit_order_issued(instance: UnitInstance, order: GameEnums.UnitOrderType)
signal unit_arrived(instance: UnitInstance, coord: Vector2i)
signal unit_moved(instance: UnitInstance, from_coord: Vector2i, to_coord: Vector2i)

@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — HexPathfinder's road/rail/canal discount, AND (Phase 2.5.4) the Zone of Control read _is_friendly_hex() gates Garrison/Hold healing on. Unset skips both gracefully.

var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _logistics_network: LogisticsNetwork
var _move_timer: float = 0.0

## Balancing number, not an architecture one — same framing as
## HordeManager.MOVE_INTERVAL_SECONDS, which this deliberately matches so a
## unit and a horde cross open ground at the same rate.
const MOVE_INTERVAL_SECONDS: float = 20.0

## Phase 2.5.4's first-ever regen mechanic — a fraction of max_hp (not a
## flat number) so a Tier 5 unit's much larger HP pool doesn't heal
## proportionally slower than a Tier 0 unit's. Placeholder balancing
## number, not an architecture decision, same framing as every other
## constant table in this project; ticks on the same MOVE_INTERVAL_SECONDS
## cadence as movement, applied only to HOLD/GARRISON units (see
## _advance_unit()) since a moving/patrolling unit never reaches this branch.
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

func _process(delta: float) -> void:
	if not _unit_manager:
		return
	_move_timer += delta
	while _move_timer >= MOVE_INTERVAL_SECONDS:
		_move_timer -= MOVE_INTERVAL_SECONDS
		for instance in _unit_manager.get_all_units():
			_advance_unit(instance)

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

## --- Movement tick --------------------------------------------------------

func _advance_unit(instance: UnitInstance) -> void:
	match instance.order:
		GameEnums.UnitOrderType.MOVE, GameEnums.UnitOrderType.ATTACK_MOVE:
			_advance_toward(instance, instance.move_target, true)
		GameEnums.UnitOrderType.PATROL:
			_advance_patrol(instance)
		GameEnums.UnitOrderType.HOLD, GameEnums.UnitOrderType.GARRISON:
			_regen_if_friendly(instance)
		_:
			pass

## `revert_to_hold_on_arrival`: true for MOVE/ATTACK_MOVE (a one-shot order
## that's "done" once the destination is reached — design doc: "then
## reverts to HOLD on arrival"), false for PATROL (arriving just advances to
## the next leg, handled by _advance_patrol() itself rather than here).
func _advance_toward(instance: UnitInstance, destination: Vector2i, revert_to_hold_on_arrival: bool) -> void:
	if instance.hex_coord == destination:
		if revert_to_hold_on_arrival:
			_set_order(instance, GameEnums.UnitOrderType.HOLD)
		return
	if instance.path.is_empty():
		_replan(instance, destination)
	if instance.path.is_empty():
		return  ## No route found this cycle (e.g. destination currently unreachable) — try again next tick.

	var next_coord: Vector2i = instance.path.pop_front()
	var from_coord := instance.hex_coord
	instance.hex_coord = next_coord
	instance.local_position = HexCoord.entry_local_position(from_coord, next_coord)  ## Phase 2.5.4.
	unit_moved.emit(instance, from_coord, next_coord)
	if next_coord == destination:
		unit_arrived.emit(instance, next_coord)
		if revert_to_hold_on_arrival:
			_set_order(instance, GameEnums.UnitOrderType.HOLD)

func _advance_patrol(instance: UnitInstance) -> void:
	if not instance.has_patrol_waypoints():
		return
	instance.patrol_target_index = wrapi(instance.patrol_target_index, 0, instance.patrol_waypoints.size())
	var target: Vector2i = instance.patrol_waypoints[instance.patrol_target_index]
	if instance.hex_coord == target:
		instance.patrol_target_index = wrapi(instance.patrol_target_index + 1, 0, instance.patrol_waypoints.size())
		return
	_advance_toward(instance, target, false)

func _replan(instance: UnitInstance, destination: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var path := HexPathfinder.find_path(_hex_grid_map, instance.hex_coord, destination, _logistics_network)
	if path.size() > 1:
		path.remove_at(0)  # path[0] is the unit's own current hex.
		instance.path = path

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
