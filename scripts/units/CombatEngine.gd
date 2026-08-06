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
## WallSegment). This is what lets whichever system eventually triggers
## combat — Phase 5.10's ATTACKING sieges, Phase 5.6's attack-move orders —
## call straight into this without CombatEngine needing to know that caller
## exists yet, the same relationship HexPathfinder has to HordeManager.
##
## No live trigger calls this yet: Phase 5.10 only reaches WANDERING today
## (see HordeManager), and Phase 5.6's orders don't exist. Built ahead of
## both callers deliberately — same "foundation built ahead of its first
## caller" position HexPathfinder was in before HordeManager arrived to use
## it, and TickManager was in before TimeCycleManager.
##
## Deliberately does NOT model the opposing side as a typed Resource: no
## "the other thing a unit can fight" data class exists anywhere in the
## project yet — a Horde's `size` (Horde.gd) is a headcount, not a combat
## stat, and the design doc itself hasn't decided zombie-side combat
## numbers ("the special role's exact combat identity... is a
## balancing/design pass", same spirit applied here). Inventing HP/damage
## numbers for a zombie now would be unreviewed balancing dressed up as
## architecture. `defender_hp`/`defender_damage` are plain floats instead —
## whichever system eventually triggers combat supplies them from whatever
## it actually represents, unit-vs-unit or unit-vs-horde alike.

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
## Returns a plain Dictionary — a single transient computation result, not
## persistent state anything needs to save, so this deliberately isn't a
## new Resource/RefCounted subtype: `damage_dealt` (to the defender),
## `defender_hp_remaining`, `attacker_hp_remaining`, and
## `attacker_forced_melee` (whether the Gunpowder-depletion penalty applied
## this round).
static func resolve_engagement(attacker: UnitInstance, attacker_gunpowder_available: bool, defender_hp: float, defender_damage: float) -> Dictionary:
	var forced_melee := attacker.definition.requires_gunpowder and not attacker_gunpowder_available

	var outgoing_damage := attacker.definition.attack_damage
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
