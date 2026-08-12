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
## Phase 2.5.4: local_position (an offset from hex_coord's center, same
## contract as BuildingInstance.local_position) extends that Phase 2.5.3
## pattern to a moving entity — written continuously, every frame, by
## UnitOrderController's MovementStepper-driven movement (user request,
## later pass — see MovementStepper.gd) as the unit actually walks, rather
## than the old hex-center jump a unit used to do on every step. ZERO
## (hex center) for a freshly-trained unit that hasn't moved yet.
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
@export var local_position: Vector2 = Vector2.ZERO  ## Offset from hex_coord's center; see HexCoord.entry_local_position().
@export var id: int = 0
@export var current_hp: float = 0.0

@export var order: GameEnums.UnitOrderType = GameEnums.UnitOrderType.HOLD
@export var move_target: Vector2i = Vector2i.ZERO       ## Meaningful only while order is MOVE/ATTACK_MOVE.
## Offset from move_target's own hex center — same contract as
## local_position (playtest round 5: "a selected unit should immediately
## move to where the user has right clicked", not just to the nearest hex's
## center). ZERO means "the hex center", which is what every move order
## used to unconditionally target before this field existed — a right-click
## dead-center of a hex, or any pre-existing save (this field defaults to
## ZERO), still behaves identically. Only the FINAL hex of a path ever
## targets this offset; every hex the unit merely passes through along the
## way still routes through its own plain center (UnitOrderController's own
## doc comment on _advance_toward() has the full reasoning).
@export var move_target_local: Vector2 = Vector2.ZERO
@export var patrol_waypoints: Array[Vector2i] = []      ## Meaningful only while order is PATROL; looped in order, index 0 first.
## Index-aligned with patrol_waypoints — same move_target_local contract,
## per waypoint, so a patrol genuinely visits the exact points the player
## clicked while recording rather than snapping every leg to a hex center.
@export var patrol_waypoint_locals: Array[Vector2] = []
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

## Design doc Phase 2.5.4, decided: "rendering splits by tier, not role" —
## Tier 0-3 (every role) render as a squad of individual figures; Tier 4-5
## (every role — the roster's named vehicles) render as one detailed model
## instead, since "a squad of siege howitzers doesn't make sense the way a
## squad of Redcoats does."
const SQUAD_SIZE: int = 5

func is_squad_rendered() -> bool:
	return definition != null and definition.tier <= 3

## Design doc Phase 2.5.4, decided: "squad headcount is derived, not new
## stored state" — ceil(current_hp / (max_hp / SQUAD_SIZE)), clamped to at
## least 1 while the unit is alive (a squad never visually reads as fully
## empty before it's actually destroyed) and at most SQUAD_SIZE. Tier 4-5
## (single-model, not squad-rendered — see is_squad_rendered()) always
## reports 1 while alive: the same "headcount ticks down by one" casualty
## hook CombatCoordinator uses for squads applies here too, it just only
## ever has one figure to lose, on the unit's own death.
func get_squad_headcount() -> int:
	if is_destroyed():
		return 0
	if not is_squad_rendered() or not definition or definition.max_hp <= 0.0:
		return 1
	return clampi(ceili(current_hp / (definition.max_hp / float(SQUAD_SIZE))), 1, SQUAD_SIZE)
