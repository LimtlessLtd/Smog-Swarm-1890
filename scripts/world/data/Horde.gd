class_name Horde
extends Resource

## One roaming zombie horde — a mobile entity with a hex position, a
## strength (size), and a behavioral state. Saved directly, same as
## WallSegment: nothing here references another live Resource, so there's
## no need for a separate save-entry wrapper the way BuildingInstance needs
## BuildingSaveEntry.
##
## Only GameEnums.HordeState.WANDERING is actually produced/transitioned to
## right now (see HordeManager) — ATTRACTED (drawn toward industrial noise
## or a lit vision source) and ATTACKING (besieging a specific wall
## segment/hex) are the rest of the state machine.
##
## Combat stats (HP_PER_ZOMBIE/DAMAGE_PER_ZOMBIE below): size alone is a
## headcount, not something CombatEngine.resolve_engagement() can compute
## an engagement from. Read/applied by CombatCoordinator, never by
## HordeManager itself — same "data class other systems mutate directly"
## role hex_coord/path play.

@export var hex_coord: Vector2i = Vector2i.ZERO
@export var size: int = 0
@export var state: GameEnums.HordeState = GameEnums.HordeState.WANDERING
@export var id: int = 0

## Offset from hex_coord's center, same contract as
## BuildingInstance.local_position/UnitInstance.local_position — written
## continuously, every frame, by HordeManager's MovementStepper-driven
## drift as the horde actually walks. ZERO for a freshly-spawned horde
## (starting seed or a fresh casualty pool) — saved directly along with
## the rest of this Resource.
@export var local_position: Vector2 = Vector2.ZERO

## Current drift path (HexPathfinder) — hex_coord itself is excluded, so
## the next hex to step into is path[0]. NOT @export: it's cheap for
## HordeManager to replan from scratch after a load (same reasoning Zone
## of Control coverage uses for not saving itself — see LogisticsNetwork),
## and a mid-path point in time isn't meaningful state worth persisting.
var path: Array[Vector2i] = []

## A Dragoon's charge (GameEnums.UnitAbility.CHARGE_KNOCKBACK) knocks a
## horde back and stuns it for a second — set by
## CombatCoordinator._apply_special_ability_effects(), decremented and
## enforced by HordeManager._advance_horde() (movement/wall-siege progress
## both pause while stunned). NOT @export, same reasoning as `path` above
## — a stun this short-lived is never meaningful state worth surviving a
## save/load; a horde reloaded mid-stun just resumes unstunned.
var stun_seconds_remaining: float = 0.0

## Placeholder balancing numbers, not an architecture decision. A modest
## per-zombie contribution: a starting horde (10-25, see HordeManager)
## fields roughly a Tier-0/1 unit's worth of HP and a fraction of its
## damage per zombie, so a lone unit can plausibly whittle down a small
## horde but a large one is a real threat.
const HP_PER_ZOMBIE: float = 2.0
const DAMAGE_PER_ZOMBIE: float = 0.5

## Real per-zombie identity — "each individual zombie should have a
## randomly generated value for how susceptible they are to stimuli... and
## it defines how easily attracted a particular zombie is to noises or
## light" (user feedback), plus per-individual movement/speed variance.
## Deterministic from (id, index) rather than a stored array — O(1)
## regardless of horde size (a horde can be thousands strong; storing a
## real per-zombie array would scale save-file size and merge/split
## bookkeeping with it), and matches this project's own established
## seeded-RNG convention (LocalDetailGenerator._hex_seed(),
## TacticalEntityLayer._scatter_offset()'s own _hash01()). A zombie's own
## values survive a save/load (id+index reproduce the exact same numbers)
## but do NOT survive a horde merge/split (indices renumber) — "which
## specific zombie used to be susceptible" was never meaningful state on
## its own, only "this horde's population skews jumpy or dull" is, and
## mean_susceptibility() below is what actually gets read.
const MIN_SUSCEPTIBILITY: float = 0.4  ## Dullest zombies — only reacts to a source roughly 2.5x louder than ATTRACTION_THRESHOLD.
const MAX_SUSCEPTIBILITY: float = 1.6  ## Jumpiest zombies — reacts to a source well under ATTRACTION_THRESHOLD.
const MIN_SPEED_VARIANCE: float = 0.85
const MAX_SPEED_VARIANCE: float = 1.2

func _individual_seed(index: int) -> int:
	return id * 92821 ^ index * 15485863  ## Large primes, same style as LocalDetailGenerator._hex_seed().

## How readily zombie #index reacts to noise/light — HordeManager reads
## mean_susceptibility() (below) to modulate the flat ATTRACTION_THRESHOLD
## per-horde, not this directly; exposed per-index so a future pass that
## DOES want a specific figure's own value (e.g. a splinter/peel-off
## mechanic) has it without redesigning the storage.
func individual_susceptibility(index: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = _individual_seed(index)
	return rng.randf_range(MIN_SUSCEPTIBILITY, MAX_SUSCEPTIBILITY)

## A zombie's own gait-speed variance — read by TacticalEntityLayer to give
## each rendered figure real, persistent (not just per-frame-random)
## individual movement character, distinct from a duller/eager neighbor.
## XORed against a different constant than individual_susceptibility()'s
## own seed so a zombie's speed and susceptibility aren't perfectly
## correlated (a jumpy zombie isn't necessarily also a fast one).
func individual_speed_variance(index: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = _individual_seed(index) ^ 0x5bd1e995
	return rng.randf_range(MIN_SPEED_VARIANCE, MAX_SPEED_VARIANCE)

## Mean susceptibility across the horde's own population, sampled rather
## than averaged over every zombie once size gets large — a Monte-Carlo
## mean over _SUSCEPTIBILITY_SAMPLE_COUNT individuals converges close
## enough for a threshold multiplier, and stays O(1) regardless of whether
## the horde is 20 strong or 5,000.
const _SUSCEPTIBILITY_SAMPLE_COUNT: int = 12
func mean_susceptibility() -> float:
	var n := mini(size, _SUSCEPTIBILITY_SAMPLE_COUNT)
	if n <= 0:
		return 1.0
	var total := 0.0
	for i in range(n):
		total += individual_susceptibility(i)
	return total / float(n)

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
## via HordeManager.remove_horde(), not this method's own job (Horde has
## no reference back to HordeManager to call that itself).
func apply_remaining_hp(remaining_hp: float) -> void:
	size = maxi(0, int(floor(remaining_hp / HP_PER_ZOMBIE)))
