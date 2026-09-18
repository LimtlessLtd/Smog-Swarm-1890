class_name WallDefenseController
extends Node

## Defenders fight a horde that is clawing at a wall piece. `PLAYER_EXPERIENCE.md`
## §5.6 and DEF-3: before this, a siege gave the player nothing to do — units only
## fought a horde standing in their own hex, which an unbreached wall prevents, so
## the "Hold the wall" moment was watching a HP number fall.
##
## Every VOLLEY_INTERVAL_SECONDS, each player unit standing on the far side of a
## sieged piece from the horde, and within reach of that piece, strikes the horde
## once through CombatCoordinator.strike_from_cover(): full outgoing damage,
## nothing back. Position is the decision — a Toxophilite reaches the piece from
## RANGED_REACH_METRES, a Truncheoneer only from the parapet (MELEE_REACH_METRES),
## so where the player stands their squad along a 5 km hex edge decides how many of
## them fight.
##
## Owns only WHEN and WHO. The damage rules stay in CombatCoordinator, which
## already owns morale, veterancy, the day bonus, research and gunpowder.

signal volley_resolved(horde: Horde, segment: WallSegment, defenders: int)

## Game-seconds between volleys. Half of CombatCoordinator's 20 s contact round:
## a defender behind a palisade is loosing into a packed mass, not trading blows
## that each take a full round. At the default 5x that is a volley every 2 real
## seconds. Balance number, measured at night in verify_wall_defense.gd: an
## undefended Wooden piece breaches under an 800-strong horde after 595
## game-seconds (119 real s at 5x); ten Toxophilites at the piece destroy that horde
## in 395 (79 real s) with 55 of 100 HP left; three lose the piece at 684 with 392
## zombies still standing.
const VOLLEY_INTERVAL_SECONDS: float = 10.0
## Metres from the wall piece's line a RANGED unit can strike from — a war bow into
## a mass at a wall, not aimed fire at a single target (design_doc.md §6 rates a
## rifle's report at 150 m; the reach of the weapon is the same order).
const RANGED_REACH_METRES: float = 200.0
## Metres for MELEE and SPECIAL units: standing at the wall itself, striking down
## over it.
const MELEE_REACH_METRES: float = 25.0
## Same catch-up cap and reason as ResidentDefenseController.MAX_TICKS_PER_FRAME.
const MAX_VOLLEYS_PER_FRAME: int = 4

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var combat_coordinator_path: NodePath

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _combat_coordinator: CombatCoordinator
var _elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  ## Background-simulation infrastructure, same as HordeManager/ResidentDefenseController.
	if unit_manager_path:
		_unit_manager = get_node_or_null(unit_manager_path) as UnitManager
	if horde_manager_path:
		_horde_manager = get_node_or_null(horde_manager_path) as HordeManager
	if combat_coordinator_path:
		_combat_coordinator = get_node_or_null(combat_coordinator_path) as CombatCoordinator


func _process(delta: float) -> void:
	_elapsed += delta
	var volleys := 0
	while _elapsed >= VOLLEY_INTERVAL_SECONDS and volleys < MAX_VOLLEYS_PER_FRAME:
		_elapsed -= VOLLEY_INTERVAL_SECONDS
		volleys += 1
		run_volley()
	if volleys >= MAX_VOLLEYS_PER_FRAME:
		_elapsed = 0.0


## One volley against every sieging horde. Public so a verification can advance it
## deterministically, the same reason ResidentDefenseController.run_wave_tick() is.
func run_volley() -> void:
	if not _unit_manager or not _horde_manager or not _combat_coordinator:
		return
	for horde in _horde_manager.get_sieging_hordes():
		var segment := _horde_manager.get_sieged_segment(horde)
		if segment == null or segment.is_breached() or horde.size <= 0:
			continue
		var defenders := get_defenders(horde, segment)
		for instance in defenders:
			if horde.size <= 0:
				break
			_combat_coordinator.strike_from_cover(instance, horde)
		volley_resolved.emit(horde, segment, defenders.size())


## Units that can strike `horde` at `segment` right now: alive, armed, within their
## role's reach of the piece, and on the other side of its line from the horde.
##
## The side is decided geometrically, not from WallSegment.hex_a/hex_b. A piece
## seeded along a hex edge (WallManager.seed_starting_defenses()) has both
## endpoints exactly on the boundary, so world_to_coord() of each can land on
## either hex. Measured on the real map (playtest vertical_slice, 2026-09-16): of
## 113 pieces seeded around (79, 119) none connected the start hex to any one of
## its six neighbours, and the first slice siege found zero defenders among ten
## units standing 15 m inside the sieged piece. Deciding by side, the same siege
## found all ten.
func get_defenders(horde: Horde, segment: WallSegment) -> Array[UnitInstance]:
	var result: Array[UnitInstance] = []
	var horde_world := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	var horde_side := side_of(segment, horde_world)
	for instance: UnitInstance in _unit_manager.get_all_units():
		if instance.is_destroyed() or instance.definition.attack_damage <= 0.0:
			continue
		var world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		if distance_to_segment_metres(world, segment) > reach_metres(instance.definition):
			continue
		if CombatCoordinator.contact_distance(instance, horde) > reach_metres(instance.definition) * HexCoord.WORLD_UNITS_PER_REAL_METER:
			continue
		if not instance.on_wall and side_of(segment, world) == horde_side:
			continue
		result.append(instance)
	return result


## -1 or +1 for which side of the piece's infinite line `world` is on; 0 on it.
static func side_of(segment: WallSegment, world: Vector2) -> int:
	return signi(int(sign((segment.point_b - segment.point_a).cross(world - segment.point_a))))


static func reach_metres(definition: UnitDefinition) -> float:
	return RANGED_REACH_METRES if definition.role == GameEnums.UnitRole.RANGED else MELEE_REACH_METRES


static func distance_to_segment_metres(world: Vector2, segment: WallSegment) -> float:
	var closest := Geometry2D.get_closest_point_to_segment(world, segment.point_a, segment.point_b)
	return world.distance_to(closest) / HexCoord.WORLD_UNITS_PER_REAL_METER
