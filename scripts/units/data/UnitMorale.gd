class_name UnitMorale
extends RefCounted

## Design doc Phase 5.7: per-unit Morale & Veterancy — **decided:** distinct
## from Phase 2.11's population-wide Discontent (`DiscontentManager`), which
## this deliberately shares no code or state with. A pure, stateless static
## utility, same shape as `CombatEngine`/`TerrainVisuals`: every input
## arrives as a value or a data Resource (`UnitInstance`) passed in by the
## caller (`CombatCoordinator`) — nothing here is a Node, nothing here is
## owned, and this never references `CombatEngine` or vice versa.
##
## Morale — the design doc's own four inputs:
##   1. Current health (fraction of max HP).
##   2. Equipment: specifically "supplied with Gunpowder right now" (Phase
##      5.4's depletion penalty). A separate per-unit weapon-tier upgrade
##      score doesn't exist as its own concept yet (Phase 2.9's per-unit
##      tech upgrades aren't built), so this input reduces to the Gunpowder
##      check alone for now — input 4 below already covers the tier-based
##      equipment-quality signal the design doc's "weapon tier" language
##      was also gesturing at.
##   3. Rank/experience (`get_rank()`, driven by `UnitInstance.kill_count`)
##      — a steadier, more battle-hardened unit has better morale, on top
##      of the separate veterancy damage bonus below.
##   4. Unit tier itself (`UnitDefinition.tier`), normalized against the
##      roster's own top tier (5) so a cheap Tier 0 Truncheoneer isn't
##      perpetually low-morale just for being early starting infantry —
##      read as "how well-equipped, for its own era", not "how advanced
##      overall".
##
## The design doc's own "reasonable fifth input" — a severe famine ratio
## (< 0.5) — is deliberately NOT wired here: it needs a live
## `BuildingManager` food-ratio reference this stateless utility doesn't
## take a dependency on. A future caller can fold it into whichever
## multiplier it passes to `CombatEngine` the same way this class's own
## outputs already are, without this file needing to change.
##
## "Low morale degrades combat effectiveness (accuracy/damage or a chance
## to rout)" — **decided here:** damage output only, not a rout/flee
## behavior (which would need `UnitOrderController` changes this phase
## isn't touching). `get_damage_multiplier()` folds morale's penalty AND
## veterancy's bonus into one scalar `CombatCoordinator` passes to
## `CombatEngine.resolve_engagement()`'s `damage_multiplier` parameter —
## applied to OUTGOING damage only, a shaky unit hits softer, it isn't
## easier to hit.

enum Rank { ROOKIE, VETERAN, ELITE }

## Placeholder balancing numbers, not an architecture decision — same
## framing as every other constant table in this project.
const VETERAN_KILLS: int = 3
const ELITE_KILLS: int = 10

const MIN_MORALE_DAMAGE_MULTIPLIER: float = 0.6  ## Floor at 0 morale — "reduced effectiveness", not "useless".
const VETERAN_DAMAGE_BONUS: float = 0.1           ## +10% outgoing damage, stacks additively with morale's own multiplier.
const ELITE_DAMAGE_BONUS: float = 0.25            ## +25%.

## "A kill counter driving a Rookie -> Veteran -> Elite-style progression"
## (design doc) — **decided:** a "kill" is destroying a Horde outright
## (`CombatCoordinator`, on `Horde.size` reaching 0), not merely damaging
## one. Hordes are a population, not discrete enemies, so there's no more
## granular unit to count a kill against.
static func get_rank(instance: UnitInstance) -> Rank:
	if instance.kill_count >= ELITE_KILLS:
		return Rank.ELITE
	if instance.kill_count >= VETERAN_KILLS:
		return Rank.VETERAN
	return Rank.ROOKIE

## 0.0 (broken) .. 1.0 (steady) — the four decided inputs above, averaged.
static func get_morale(instance: UnitInstance, gunpowder_available: bool) -> float:
	if not instance.definition or instance.definition.max_hp <= 0.0:
		return 1.0

	var hp_factor := instance.current_hp / instance.definition.max_hp

	var equipment_factor := 1.0
	if instance.definition.requires_gunpowder and not gunpowder_available:
		equipment_factor = 0.5  # Forced into fragile melee mode (CombatEngine) — shaky, not just under-equipped.

	var rank_factor: float
	match get_rank(instance):
		Rank.ELITE:
			rank_factor = 1.0
		Rank.VETERAN:
			rank_factor = 0.85
		_:
			rank_factor = 0.7  # Rookie — steadier than raw panic, but genuinely green.

	var tier_factor: float = 0.6 + 0.4 * (float(instance.definition.tier) / 5.0)  # Tier 0 -> 0.6, Tier 5 -> 1.0.

	return clampf((hp_factor + equipment_factor + rank_factor + tier_factor) / 4.0, 0.0, 1.0)

## The single scalar `CombatCoordinator` passes to
## `CombatEngine.resolve_engagement()`'s `damage_multiplier` — morale's
## penalty and veterancy's bonus combined into one number so `CombatEngine`
## itself needs only one extra parameter, not two, and never has to know
## this class (or ranks, or kill counts) exists at all.
static func get_damage_multiplier(instance: UnitInstance, gunpowder_available: bool) -> float:
	var morale := get_morale(instance, gunpowder_available)
	var morale_multiplier: float = lerpf(MIN_MORALE_DAMAGE_MULTIPLIER, 1.0, morale)

	var veterancy_bonus := 0.0
	match get_rank(instance):
		Rank.ELITE:
			veterancy_bonus = ELITE_DAMAGE_BONUS
		Rank.VETERAN:
			veterancy_bonus = VETERAN_DAMAGE_BONUS
		_:
			pass

	return morale_multiplier + veterancy_bonus
