class_name UnitDefinition
extends Resource

## Pure data template for one entry in the unit roster — "what a Redcoat
## is", not "the Redcoat garrisoned at hex (7,6)" (that's UnitInstance).
## Populated once by UnitCatalog, queried by UnitManager for training
## validation/cost and by CombatEngine for combat stats. Mirrors
## BuildingDefinition's shape and role — same "pure data, no logic beyond
## simple derived queries" convention.

@export var unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER
@export var display_name: String = ""
@export var tier: int = 0  ## 0-5, matches TechManager.is_unit_tier_unlocked()'s tier numbering exactly.
@export var role: GameEnums.UnitRole = GameEnums.UnitRole.MELEE

@export var training_cost: Dictionary = {}  ## GameEnums.ResourceType -> int, paid once when UnitManager trains one.
@export var daily_upkeep: Dictionary = {}   ## GameEnums.ResourceType -> float. Gunpowder only, and only where requires_gunpowder is true — see that field.

@export var max_hp: float = 10.0
@export var attack_damage: float = 1.0

## The Gunpowder depletion penalty applies to every firearm-era ranged
## unit (Yeoman Marksman and above) — 0 ammo forces fragile, unarmored
## melee mode. Tier 0's Toxophilite is exempt by design (arrows aren't a
## resource the game tracks). True for every RANGED-role unit from Tier 1
## up; false for Toxophilite specifically and for every MELEE/SPECIAL-role
## unit — the penalty is scoped to "ranged" units only, it doesn't claim
## every special-role unit is unarmed, just that this specific mechanic
## doesn't apply to them. CombatEngine reads this alongside a
## caller-supplied "is Gunpowder available right now" flag (colony-wide
## stockpile, not a per-unit ammo pool — ResourceType.GUNPOWDER is already
## a single shared resource everywhere else in the project) to decide
## whether an attack lands at full ranged effectiveness or gets knocked
## into the fragile melee-mode penalty.
@export var requires_gunpowder: bool = false

## "Each special unit type should do something special" (user feedback).
## Originally SPECIAL-exclusive; Tier 4-5's Traction Ram and Holt Breaker
## (both MELEE) now carry TRAMPLE_KNOCKBACK too — a real mechanic grounded
## in their own art/description ("crush obstacles under its immense
## weight"), not a role restriction that still holds. NONE for every unit
## without a distinct mechanic (most MELEE/RANGED units, and any SPECIAL
## unit not yet given one) — see GameEnums.UnitAbility's own doc comment
## for what each real value does and which system reads it.
@export var ability: GameEnums.UnitAbility = GameEnums.UnitAbility.NONE

## Stacks multiplicatively with terrain/logistics/Day-Night speed factors —
## see UnitOrderController._movement_speed(). 1.0 = no change (most units);
## mounted SPECIAL units (Outrider, Chasseur, Dragoon) run faster than an
## unmounted soldier, and Tier 4-5's vehicles lean the same way their own
## description implies — quicker for a light wheeled vehicle (Maxim
## Quadricycle, Armoured Command Car), slower for something that
## "slow-rolls" under its own weight (Traction Ram, Holt Breaker, Field
## Howitzer Gun Tractor).
@export var move_speed_multiplier: float = 1.0

## Hex-disk radius this unit projects VISIBLE coverage over, centered on
## its own hex — same "0 still means own hex is visible" contract as
## BuildingDefinition.vision_radius (that field's own doc comment), read
## by FogOfWarManager the identical way for a building. Default 0 for most
## of the roster. Outrider is the one deliberate exception:
## UnitAbility.UNARMED_SCOUT's own doc comment already frames it as "fast
## mounted vision/recon only" — see UnitCatalog's own comment on that unit
## for the value.
@export var vision_radius: int = 0

func _init(p_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER, p_display_name: String = "", p_tier: int = 0, p_role: GameEnums.UnitRole = GameEnums.UnitRole.MELEE) -> void:
	unit_type = p_type
	display_name = p_display_name
	tier = p_tier
	role = p_role
