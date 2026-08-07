class_name Horde
extends Resource

## One roaming zombie horde (design doc Phase 5.2/5.10) — a mobile entity
## with a hex position, a strength (`size`), and a behavioral state. Saved
## directly, same as WallSegment: nothing here references another live
## Resource, so there's no need for a separate save-entry wrapper the way
## BuildingInstance needs BuildingSaveEntry.
##
## Only GameEnums.HordeState.WANDERING is actually produced/transitioned to
## right now (see HordeManager) — ATTRACTED (drawn toward industrial noise
## or a lit vision source) and ATTACKING (besieging a specific wall
## segment/hex) are the rest of Phase 5.10's state machine, blocked on
## Phase 5.2's still-nonexistent noise tracking and Phase 5.10's still-
## nonexistent siege-seeking behavior respectively. The enum values exist
## now so wiring them up later is additive, not a breaking rename.
##
## Combat stats (HP_PER_ZOMBIE/DAMAGE_PER_ZOMBIE below): the horde-combat-
## stat decision every Phase 5.4/5.6/5.9/5.10 "no live combat trigger
## exists" note has been pointing at — `size` alone is a headcount, not
## something CombatEngine.resolve_engagement() can compute an engagement
## from. Read/applied by the new CombatCoordinator (Phase 5.4/5.9/5.10's
## live combat trigger), never by HordeManager itself — same "data class
## other systems mutate directly" role hex_coord/path already play.

@export var hex_coord: Vector2i = Vector2i.ZERO
@export var size: int = 0
@export var state: GameEnums.HordeState = GameEnums.HordeState.WANDERING
@export var id: int = 0

## Phase 2.5.4: offset from hex_coord's center, same contract as
## BuildingInstance.local_position/UnitInstance.local_position — written by
## HordeManager's drift tick via HexCoord.entry_local_position() every time
## hex_coord changes, instead of the hex-center jump a horde used to do on
## every step. ZERO for a freshly-spawned horde (starting seed or a fresh
## casualty pool) — saved directly along with the rest of this Resource,
## same as every other field here.
@export var local_position: Vector2 = Vector2.ZERO

## Current drift path (Phase 5.5's HexPathfinder) — `hex_coord` itself is
## excluded, so the next hex to step into is `path[0]`. Deliberately NOT
## @export: it's cheap for HordeManager to replan from scratch after a load
## (same reasoning Zone of Control coverage uses for not saving itself —
## see LogisticsNetwork), and a mid-path point in time isn't meaningful
## state worth persisting anyway.
var path: Array[Vector2i] = []

## Placeholder balancing numbers, not an architecture decision — same
## framing as every other constant table in this project (UnitCatalog's
## per-tier curve, CombatEngine's forced-melee multipliers). A modest
## per-zombie contribution: a starting horde (10-25, see HordeManager)
## fields roughly a Tier-0/1 unit's worth of HP and a fraction of its
## damage per zombie, so a lone unit can plausibly whittle down a small
## horde but a large one is a real threat — exact numbers are for
## playtesting to retune, not for this decision to get "right" up front.
const HP_PER_ZOMBIE: float = 2.0
const DAMAGE_PER_ZOMBIE: float = 0.5

func _init(p_hex_coord: Vector2i = Vector2i.ZERO, p_size: int = 0, p_id: int = 0, p_state: GameEnums.HordeState = GameEnums.HordeState.WANDERING) -> void:
	hex_coord = p_hex_coord
	size = p_size
	id = p_id
	state = p_state

func get_combat_hp() -> float:
	return size * HP_PER_ZOMBIE

func get_combat_damage() -> float:
	return size * DAMAGE_PER_ZOMBIE

## Converts a post-engagement HP total back into a headcount — floor
## division against HP_PER_ZOMBIE, since a fraction of a zombie's worth of
## HP remaining doesn't leave a fractional zombie standing. Never goes
## negative; a horde reduced to 0 is CombatCoordinator's cue to remove it
## via HordeManager.remove_horde(), not this method's own job (Horde has no
## reference back to HordeManager to call that itself).
func apply_remaining_hp(remaining_hp: float) -> void:
	size = maxi(0, int(floor(remaining_hp / HP_PER_ZOMBIE)))
