class_name UnitDefinition
extends Resource

## Pure data template for one entry in the unit roster (design doc Phase
## 5.4) — "what a Redcoat is", not "the Redcoat garrisoned at hex (7,6)"
## (that's UnitInstance). Populated once by UnitCatalog, queried by
## UnitManager for training validation/cost and by CombatEngine for combat
## stats. Deliberately mirrors BuildingDefinition's shape and role — same
## "pure data, no logic beyond simple derived queries" convention.
##
## No movement-speed/vision-radius/local-position-style fields yet: nothing
## in this codebase reads them (Phase 5.5's tactical-scale movement and
## Phase 5.6's unit orders are still unbuilt), and this project's own
## practice is not adding a field ahead of an actual reader — see every
## other Definition/Catalog pair's own restraint on this. Add them when
## whichever phase needs them actually lands, same as BuildingDefinition's
## own vision_radius arrived with Phase 2.6, not before.

@export var unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER
@export var display_name: String = ""
@export var tier: int = 0  ## 0-5, matches TechManager.is_unit_tier_unlocked()'s tier numbering exactly.
@export var role: GameEnums.UnitRole = GameEnums.UnitRole.MELEE

@export var training_cost: Dictionary = {}  ## GameEnums.ResourceType -> int, paid once when UnitManager trains one.
@export var daily_upkeep: Dictionary = {}   ## GameEnums.ResourceType -> float. Gunpowder only, and only where requires_gunpowder is true — see that field.

@export var max_hp: float = 10.0
@export var attack_damage: float = 1.0

## Design doc, decided: "Strict Gunpowder depletion penalty applies to every
## firearm-era ranged unit (Yeoman Marksman and above) — 0 ammo forces
## fragile, unarmored melee mode. Tier 0's Toxophilite is exempt by design
## (arrows aren't a resource the game tracks)." True for every RANGED-role
## unit from Tier 1 up; false for Toxophilite specifically and for every
## MELEE/SPECIAL-role unit (the design doc scopes the penalty to "ranged"
## units only — it does not claim every special-role unit is unarmed, just
## that this specific mechanic doesn't apply to them). CombatEngine reads
## this alongside a caller-supplied "is Gunpowder available right now" flag
## (colony-wide stockpile, not a per-unit ammo pool — ResourceType.GUNPOWDER
## is already a single shared resource everywhere else in the project) to
## decide whether an attack lands at full ranged effectiveness or gets
## knocked into the fragile melee-mode penalty.
@export var requires_gunpowder: bool = false

func _init(p_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER, p_display_name: String = "", p_tier: int = 0, p_role: GameEnums.UnitRole = GameEnums.UnitRole.MELEE) -> void:
	unit_type = p_type
	display_name = p_display_name
	tier = p_tier
	role = p_role
