class_name UnitInstance
extends Resource

## A single trained unit: a reference to its UnitDefinition template, the
## hex it currently occupies, a unique id assigned by UnitManager, and its
## current HP. Mirrors BuildingInstance's shape/role, with one difference:
## combat HP lives here now rather than being a "later-phase concern" the
## way BuildingInstance's own doc comment defers it — Phase 5.4 (this
## phase) is specifically the one introducing combat math (CombatEngine),
## so a unit needs somewhere to record damage from turn one.
##
## No local_position (Phase 2.5's Tactical-view exact-placement field on
## BuildingInstance) yet — a trained unit sits at hex granularity until
## Phase 5.5's tactical-scale movement gives it a reason to occupy a
## precise point within a hex.
##
## Phase 5.6 order state (order/move_target/patrol_waypoints): written by
## UnitManager (a fresh unit seeded from a rally point) and
## UnitOrderController (player-issued orders, and the movement tick that
## carries them out), read by UnitOrderController — same "data class other
## systems mutate directly" role Horde.hex_coord/Horde.path already play
## for HordeManager. UnitInstance itself has no logic over these beyond the
## trivial has_patrol_waypoints() query below.

@export var definition: UnitDefinition
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var id: int = 0
@export var current_hp: float = 0.0

@export var order: GameEnums.UnitOrderType = GameEnums.UnitOrderType.HOLD
@export var move_target: Vector2i = Vector2i.ZERO       ## Meaningful only while order is MOVE/ATTACK_MOVE.
@export var patrol_waypoints: Array[Vector2i] = []      ## Meaningful only while order is PATROL; looped in order, index 0 first.
var patrol_target_index: int = 0                        ## Not @export — cheap to restart a patrol loop from its first leg after a load rather than persist exact progress, same "not worth saving" call Horde.path makes.

## Current movement path (Phase 5.5's HexPathfinder) toward move_target or
## the active patrol leg — hex_coord itself excluded, so the next hex to
## step into is path[0]. Not @export, same reasoning as Horde.path: cheap
## for UnitOrderController to replan from scratch after a load.
var path: Array[Vector2i] = []

## Phase 5.7: incremented by CombatCoordinator each time this unit destroys
## a Horde outright (see UnitMorale.get_rank()'s own doc comment for why
## that's the decided definition of "a kill" against a population rather
## than a discrete enemy). Genuinely mutable per-instance state — persisted,
## same as current_hp.
@export var kill_count: int = 0

func _init(p_definition: UnitDefinition = null, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_current_hp: float = -1.0) -> void:
	definition = p_definition
	hex_coord = p_hex_coord
	id = p_id
	# -1.0 is "not specified" (a fresh training) — seed at the definition's
	# full health. A save-restore path passes the actual saved value
	# instead, same -1-sentinel convention BuildingInstance/WallSegment use.
	current_hp = p_current_hp if p_current_hp >= 0.0 else (p_definition.max_hp if p_definition else 0.0)

func is_destroyed() -> bool:
	return current_hp <= 0.0

func has_patrol_waypoints() -> bool:
	return not patrol_waypoints.is_empty()
