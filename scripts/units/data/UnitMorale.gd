class_name UnitMorale
extends RefCounted

## Per-unit Morale & Veterancy — distinct from population-wide Discontent
## (DiscontentManager), sharing no code or state with it. A pure, stateless
## static utility, same shape as CombatEngine/TerrainVisuals: every input
## arrives as a value or a data Resource (UnitInstance) passed in by the
## caller (CombatCoordinator) — nothing here is a Node, nothing here is
## owned, and this never references CombatEngine or vice versa.
##
## Morale, four inputs:
##   1. Current health (fraction of max HP).
##   2. Equipment: specifically "supplied with Gunpowder right now" (the
##      depletion penalty). A separate per-unit weapon-tier upgrade score
##      doesn't exist as its own concept yet, so this input reduces to the
##      Gunpowder check alone — input 4 below covers the tier-based
##      equipment-quality signal.
##   3. Rank/experience (get_rank(), driven by UnitInstance.kill_count) — a
##      steadier, more battle-hardened unit has better morale, on top of
##      the separate veterancy damage bonus below.
##   4. Unit tier itself (UnitDefinition.tier), normalized against the
##      roster's own top tier (5) so a cheap Tier 0 Truncheoneer isn't
##      perpetually low-morale just for being early starting infantry —
##      read as "how well-equipped, for its own era", not "how advanced overall".
##
## A "reasonable fifth input" — a severe famine ratio (< 0.5) — is NOT
## wired here: it needs a live BuildingManager food-ratio reference this
## stateless utility doesn't take a dependency on. A future caller can
## fold it into whichever multiplier it passes to CombatEngine the same
## way this class's own outputs already are, without this file needing to change.
##
## Low morale degrades combat effectiveness: damage output only, not a
## rout/flee behavior (which would need UnitOrderController changes).
## get_damage_multiplier() folds morale's penalty AND veterancy's bonus
## into one scalar CombatCoordinator passes to
## CombatEngine.resolve_engagement()'s damage_multiplier parameter —
## applied to OUTGOING damage only, a shaky unit hits softer, it isn't
## easier to hit.

enum Rank { ROOKIE, VETERAN, ELITE }

const VETERAN_KILLS: int = 3
const ELITE_KILLS: int = 10

const MIN_MORALE_DAMAGE_MULTIPLIER: float = 0.6  ## Floor at 0 morale — "reduced effectiveness", not "useless".
const VETERAN_DAMAGE_BONUS: float = 0.1           ## +10% outgoing damage, stacks additively with morale's own multiplier.
const ELITE_DAMAGE_BONUS: float = 0.25            ## +25%.

## A "kill" is destroying a Horde outright (CombatCoordinator, on
## Horde.size reaching 0), not merely damaging one. Hordes are a
## population, not discrete enemies, so there's no more granular unit to
## count a kill against.
static func get_rank(instance: UnitInstance) -> Rank:
	if instance.kill_count >= ELITE_KILLS:
		return Rank.ELITE
	if instance.kill_count >= VETERAN_KILLS:
		return Rank.VETERAN
	return Rank.ROOKIE

## 0.0 (broken) .. 1.0 (steady) — the four inputs above, averaged.
##
## `effective_max_hp` defaults to -1.0, meaning "use the definition's own
## max_hp" — i.e. exactly the behavior before per-unit upgrades existed. A
## caller that knows about researched upgrades (CombatCoordinator, via
## UnitUpgrades.max_hp()) passes the real ceiling instead, so an upgraded
## unit isn't scored as though it were permanently over-healthy. Supplied as
## a plain caller-computed scalar rather than a TechManager reference, the
## same convention CombatEngine's own multipliers use — this stays a pure
## stat helper that knows nothing about research.
static func get_morale(instance: UnitInstance, gunpowder_available: bool, effective_max_hp: float = -1.0) -> float:
	if not instance.definition:
		return 1.0
	var max_hp := effective_max_hp if effective_max_hp >= 0.0 else instance.definition.max_hp
	if max_hp <= 0.0:
		return 1.0

	var hp_factor := instance.current_hp / max_hp

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

## The single scalar CombatCoordinator passes to
## CombatEngine.resolve_engagement()'s damage_multiplier — morale's
## penalty and veterancy's bonus combined into one number so CombatEngine
## itself needs only one extra parameter, not two, and never has to know
## this class (or ranks, or kill counts) exists at all.
static func get_damage_multiplier(instance: UnitInstance, gunpowder_available: bool, effective_max_hp: float = -1.0) -> float:
	var morale := get_morale(instance, gunpowder_available, effective_max_hp)
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
