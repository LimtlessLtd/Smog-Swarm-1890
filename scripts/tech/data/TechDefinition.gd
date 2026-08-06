class_name TechDefinition
extends Resource

## Pure data template for one node in the Tech Tree (design doc Phase 2.9.2) —
## "what Concrete Walls is", not "the fact that this campaign has researched
## it" (that's TechManager). Populated once by TechCatalog, queried by
## TechManager for research validation and by whatever later phase actually
## consumes the unlock (Phase 4.1 wall construction, Phase 5.4 unit
## training) once those systems exist to check it. Mirrors
## BuildingDefinition's role for the building tree.

@export var tech_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

@export var cost: Dictionary = {}       ## GameEnums.ResourceType -> float, paid once when research starts (Research Points + often a construction material, per design doc).
@export var research_days: int = 1      ## In-game days (TickManager.day_completed) the node takes to complete once started — matches the project's existing day-granularity tick rather than a new timer system.

@export var prerequisites: Array[StringName] = []  ## Other tech_ids that must already be researched — a simple chain per node, not a wide branching web (design doc: "matches the project's grounded, non-sprawling scope").

@export var unlock_type: GameEnums.TechUnlockType = GameEnums.TechUnlockType.UNIT_TIER
@export var unlock_value: int = 0  ## Meaning depends on unlock_type — see GameEnums.TechUnlockType's own field comments.

## True only for Seafaring (design doc 2.9.2, decided): gated on campaign
## state — Wales AND Scotland both fully retaken (Phase 5.8's recapture
## state) — in addition to (not instead of) the ordinary prerequisites
## chain above. No CampaignManager (Phase 7.2) exists yet to query
## directly, so TechManager checks this via its own settable flag; see
## TechManager.set_wales_and_scotland_retaken().
@export var requires_wales_and_scotland_retaken: bool = false

func _init(p_tech_id: StringName = &"", p_display_name: String = "") -> void:
	tech_id = p_tech_id
	display_name = p_display_name
