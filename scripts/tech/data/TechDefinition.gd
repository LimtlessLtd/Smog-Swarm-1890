class_name TechDefinition
extends Resource

## Pure data template for one node in the Tech Tree —
## "what Concrete Walls is", not "the fact that this campaign has researched
## it" (that's TechManager). Populated once by TechCatalog, queried by
## TechManager for research validation and by whatever system actually
## consumes the unlock (wall construction, unit training) once it exists
## to check it. Mirrors BuildingDefinition's role for the building tree.

@export var tech_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

@export var cost: Dictionary = {}       ## GameEnums.ResourceType -> float, paid once when research starts (Research Points + often a construction material, per design doc).
@export var research_days: int = 1      ## In-game days (TickManager.day_completed) the node takes to complete once started — matches the project's existing day-granularity tick rather than a new timer system.

@export var prerequisites: Array[StringName] = []  ## Other tech_ids that must already be researched — a simple chain per node, not a wide branching web ("matches the project's grounded, non-sprawling scope" — design doc).

@export var unlock_type: GameEnums.TechUnlockType = GameEnums.TechUnlockType.UNIT_TIER
@export var unlock_value: int = 0  ## Meaning depends on unlock_type — see GameEnums.TechUnlockType's own field comments.

## True only for Seafaring: gated on campaign state — Wales AND Scotland
## both fully retaken — in addition to (not instead of) the ordinary
## prerequisites chain above. No CampaignManager exists yet to query
## directly, so TechManager checks this via its own settable flag; see
## TechManager.set_wales_and_scotland_retaken().
@export var requires_wales_and_scotland_retaken: bool = false

func _init(p_tech_id: StringName = &"", p_display_name: String = "") -> void:
	tech_id = p_tech_id
	display_name = p_display_name
