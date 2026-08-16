class_name UnitUpgradeDefinition
extends Resource

## Pure data template for ONE of a unit type's two research upgrades —
## "what Redcoat Volley Discipline is", not "has this campaign researched
## it" (that's TechManager, keyed by `tech_id` like every other node).
## Populated once by UnitUpgradeCatalog; the effect fields are read by
## UnitUpgrades (the derived-stat resolver), the tech fields by
## TechCatalog, which merges these into the one tech tree.
##
## Carries its own tech metadata (cost/research_days/prerequisites) rather
## than pairing each upgrade with a hand-written TechDefinition elsewhere:
## with 36 of these generated from the roster, two parallel tables would be
## two things to keep in sync. to_tech_definition() below is the single
## conversion point.

@export var unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER
@export var upgrade_index: int = 0  ## 0 or 1 — which of this unit's two upgrades. Also drives the prerequisite chain (index 1 requires index 0).

@export var tech_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

@export var stat: GameEnums.UnitUpgradeStat = GameEnums.UnitUpgradeStat.ATTACK_DAMAGE
## Meaning depends on `stat` — a multiplier for ATTACK_DAMAGE/MAX_HP/
## MOVE_SPEED, a 0..1 relief fraction for GUNPOWDER_RELIEF, a flat hex-ring
## count for VISION_RADIUS. See GameEnums.UnitUpgradeStat's own per-value
## comments.
@export var magnitude: float = 1.0

@export var cost: Dictionary = {}  ## GameEnums.ResourceType -> float, same shape and payment point as TechDefinition.cost.
@export var research_days: int = 1
@export var prerequisites: Array[StringName] = []

## Builds the TechDefinition TechCatalog publishes for this upgrade, so
## TechManager researches it through exactly the same start/progress/complete
## path every other node uses — nothing about research flow is special-cased
## for unit upgrades. unlock_value carries the UnitType ordinal; the upgrade
## INDEX deliberately isn't encoded into it (see
## GameEnums.TechUnlockType.UNIT_UPGRADE's own comment) — a consumer that
## needs the effect looks this definition up by tech_id instead.
func to_tech_definition() -> TechDefinition:
	var d := TechDefinition.new(tech_id, display_name)
	d.description = description
	d.cost = cost
	d.research_days = research_days
	d.prerequisites = prerequisites
	d.unlock_type = GameEnums.TechUnlockType.UNIT_UPGRADE
	d.unlock_value = int(unit_type)
	return d
