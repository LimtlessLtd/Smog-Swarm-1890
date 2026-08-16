class_name CombatEngine
extends RefCounted

## Combat resolution — the "resolve an attack" half, deliberately separate
## from UnitManager (the "who exists" half). A pure, stateless static
## utility, same shape as HexPathfinder: no NodePath exports, no _ready(),
## no reference to UnitManager, HordeManager, ResourceManager, or any other
## runtime Node — every input arrives as a plain value or a plain data
## Resource (UnitInstance) passed in by the caller, and the only side
## effect is mutating that same UnitInstance's current_hp (the "manager
## mutates a passed-in Resource directly" pattern
## WallManager.damage_segment() uses on WallSegment). This is what let
## CombatCoordinator call straight into this the moment it existed,
## without CombatEngine ever needing to know that caller was coming — the
## same relationship HexPathfinder had to HordeManager before HordeManager
## arrived to use it.
##
## Doesn't model the opposing side as a typed Resource: defender_hp/
## defender_damage are plain floats, not a "the other thing a unit can
## fight" data class — CombatCoordinator derives them from
## Horde.get_combat_hp()/get_combat_damage() today, but any future
## defender (a building's HP) can supply the same two numbers without this
## signature changing.

## "0 ammo forces fragile, unarmored melee mode" is two separate
## multipliers: outgoing damage drops ("fragile" — a rifle butt/bayonet
## still does something, so not 0), incoming damage rises ("unarmored").
## Balancing numbers, not architecture.
const FORCED_MELEE_DAMAGE_MULTIPLIER: float = 0.5       ## Outgoing damage while forced into melee mode.
const FORCED_MELEE_DAMAGE_TAKEN_MULTIPLIER: float = 1.5 ## Incoming damage while forced into melee mode.

## Resolves one round of mutual combat between `attacker` (mutated in
## place — current_hp is reduced by whatever damage it takes this round)
## and an opposing side described by `defender_hp`/`defender_damage`.
##
## `attacker_gunpowder_available` is a plain caller-supplied bool, not a
## live ResourceManager reference — see UnitDefinition.requires_gunpowder's
## own doc comment for why (a colony-wide stockpile check, not a per-unit
## ammo pool). Ignored entirely unless attacker.definition.requires_gunpowder
## is true: Toxophilite and every melee/special unit fight at full strength
## regardless of Gunpowder stock, by design.
##
## `damage_multiplier` (default 1.0, i.e. no effect) is likewise a plain
## caller-supplied float, not a live reference to whatever computed it —
## CombatCoordinator derives it from UnitMorale.get_damage_multiplier()
## (morale penalty and veterancy bonus, folded into one number) today, but
## this signature doesn't care what produced it. Applied to OUTGOING
## damage only, before the forced-melee multiplier below.
##
## `incoming_damage_multiplier` (default 1.0) is the same shape of
## caller-supplied scalar, applied to INCOMING damage instead — the
## stationary defense bonus / Searchlight Tower "granting combat bonuses to
## garrisoned units". CombatCoordinator derives it from whether the
## attacker's own order is GARRISON (and, further, whether a Searchlight
## Tower lights the position at night); this signature again doesn't care
## what produced it — same "manager mutates a passed-in Resource, engine
## stays ignorant of why" split every other combat multiplier here keeps.
##
## Returns a plain Dictionary — a single transient computation result, not
## persistent state anything needs to save, so this deliberately isn't a
## new Resource/RefCounted subtype: damage_dealt (to the defender),
## defender_hp_remaining, attacker_hp_remaining, and attacker_forced_melee
## (whether the Gunpowder-depletion penalty applied this round).
## `forced_melee_outgoing`/`forced_melee_incoming` default to the two
## constants above, i.e. exactly the behavior before they were parameters.
## They exist for the RANGED per-unit "Munitions Discipline" upgrade, which
## softens the depletion penalty rather than removing it — supplied by the
## caller (CombatCoordinator, via UnitUpgrades.forced_melee_multipliers())
## for the same reason every other multiplier here is: this engine stays
## ignorant of what computed it. Passed as a PAIR because the penalty is a
## pair; easing only the outgoing half would change what the mechanic means.
static func resolve_engagement(attacker: UnitInstance, attacker_gunpowder_available: bool, defender_hp: float, defender_damage: float, damage_multiplier: float = 1.0, incoming_damage_multiplier: float = 1.0, forced_melee_outgoing: float = FORCED_MELEE_DAMAGE_MULTIPLIER, forced_melee_incoming: float = FORCED_MELEE_DAMAGE_TAKEN_MULTIPLIER) -> Dictionary:
	var forced_melee := attacker.definition.requires_gunpowder and not attacker_gunpowder_available

	var outgoing_damage := attacker.definition.attack_damage * damage_multiplier
	if forced_melee:
		outgoing_damage *= forced_melee_outgoing

	var incoming_damage := defender_damage
	if forced_melee:
		incoming_damage *= forced_melee_incoming
	incoming_damage *= incoming_damage_multiplier

	var defender_hp_remaining := maxf(defender_hp - outgoing_damage, 0.0)
	attacker.current_hp = maxf(attacker.current_hp - incoming_damage, 0.0)

	return {
		"damage_dealt": outgoing_damage,
		"defender_hp_remaining": defender_hp_remaining,
		"attacker_hp_remaining": attacker.current_hp,
		"attacker_forced_melee": forced_melee,
	}
