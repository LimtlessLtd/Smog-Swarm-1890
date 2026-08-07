class_name CombatEngine
extends RefCounted

## Design doc Phase 5.4's combat resolution — the "resolve an attack" half
## of that phase, deliberately separate from UnitManager (the "who exists"
## half). A pure, stateless static utility, same shape as HexPathfinder:
## no NodePath exports, no `_ready()`, no reference to UnitManager,
## HordeManager, ResourceManager, or any other runtime Node — every input
## arrives as a plain value or a plain data Resource (UnitInstance) passed
## in by the caller, and the only side effect is mutating that same
## UnitInstance's current_hp (the "manager mutates a passed-in Resource
## directly" pattern WallManager.damage_segment() already uses on
## WallSegment). This is what let the new CombatCoordinator (Phase
## 5.4/5.9/5.10's live combat trigger) call straight into this the moment
## it existed, without CombatEngine ever needing to know that caller was
## coming — the same relationship HexPathfinder had to HordeManager before
## HordeManager arrived to use it, now realized a second time.
##
## Deliberately does NOT model the opposing side as a typed Resource:
## `defender_hp`/`defender_damage` are plain floats, not a "the other thing
## a unit can fight" data class — CombatCoordinator derives them from
## Horde.get_combat_hp()/get_combat_damage() today, but any future
## defender (a building's HP, Phase 5.12) can supply the same two numbers
## without this signature changing.

## "0 ammo forces fragile, unarmored melee mode" (design doc, decided) is
## two separate multipliers: outgoing damage drops ("fragile" — a rifle
## butt/bayonet still does something, so not 0), incoming damage rises
## ("unarmored"). Balancing numbers, not architecture — same framing as
## every other placeholder constant table in this project.
const FORCED_MELEE_DAMAGE_MULTIPLIER: float = 0.5       ## Outgoing damage while forced into melee mode.
const FORCED_MELEE_DAMAGE_TAKEN_MULTIPLIER: float = 1.5 ## Incoming damage while forced into melee mode.

## Resolves one round of mutual combat between `attacker` (mutated in
## place — current_hp is reduced by whatever damage it takes this round)
## and an opposing side described by `defender_hp`/`defender_damage`.
##
## `attacker_gunpowder_available` is a plain caller-supplied bool, not a
## live ResourceManager reference — see UnitDefinition.requires_gunpowder's
## own doc comment for why (a colony-wide stockpile check, not a per-unit
## ammo pool). Ignored entirely unless `attacker.definition.requires_gunpowder`
## is true: Toxophilite and every melee/special unit fight at full strength
## regardless of Gunpowder stock, by design.
##
## `damage_multiplier` (default 1.0, i.e. no effect) is likewise a plain
## caller-supplied float, not a live reference to whatever computed it —
## `CombatCoordinator` derives it from `UnitMorale.get_damage_multiplier()`
## (Phase 5.7's morale penalty and veterancy bonus, folded into one number)
## today, but this signature doesn't care what produced it. Applied to
## OUTGOING damage only, before the forced-melee multiplier below.
##
## Returns a plain Dictionary — a single transient computation result, not
## persistent state anything needs to save, so this deliberately isn't a
## new Resource/RefCounted subtype: `damage_dealt` (to the defender),
## `defender_hp_remaining`, `attacker_hp_remaining`, and
## `attacker_forced_melee` (whether the Gunpowder-depletion penalty applied
## this round).
static func resolve_engagement(attacker: UnitInstance, attacker_gunpowder_available: bool, defender_hp: float, defender_damage: float, damage_multiplier: float = 1.0) -> Dictionary:
	var forced_melee := attacker.definition.requires_gunpowder and not attacker_gunpowder_available

	var outgoing_damage := attacker.definition.attack_damage * damage_multiplier
	if forced_melee:
		outgoing_damage *= FORCED_MELEE_DAMAGE_MULTIPLIER

	var incoming_damage := defender_damage
	if forced_melee:
		incoming_damage *= FORCED_MELEE_DAMAGE_TAKEN_MULTIPLIER

	var defender_hp_remaining := maxf(defender_hp - outgoing_damage, 0.0)
	attacker.current_hp = maxf(attacker.current_hp - incoming_damage, 0.0)

	return {
		"damage_dealt": outgoing_damage,
		"defender_hp_remaining": defender_hp_remaining,
		"attacker_hp_remaining": attacker.current_hp,
		"attacker_forced_melee": forced_melee,
	}
