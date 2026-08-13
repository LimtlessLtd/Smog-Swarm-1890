class_name TechManager
extends Node

## Runtime owner of a campaign's Tech Tree progress — gates wall-tier and
## unit-tier unlocks, which both assume a research gate exists somewhere.
## Wired as a Main.tscn sibling via an exported NodePath, same pattern as
## every other manager (BuildingManager/LogisticsNetwork/FogOfWarManager/...).
##
## The tech *tree* itself (what each node costs/unlocks/requires) lives in
## TechCatalog — this class only tracks which nodes a campaign has actually
## researched, and which one (if any) is currently in progress. Only one
## node researches at a time, matching the design doc's "simple prerequisite
## chain... not a wide branching web" — no parallel research queue.
##
## Research spends its cost up front (Research Points + often a construction
## material, same as a building's construction_cost) when start_research()
## succeeds, then counts down `research_days` on TickManager.day_completed —
## the project's existing day-granularity tick, not a new timer system.

signal research_started(tech_id: StringName)
signal research_progress_changed(tech_id: StringName, days_remaining: int, research_days: int)
signal tech_researched(tech_id: StringName)
signal research_rejected(tech_id: StringName, reason: String)

@export var resource_manager_path: NodePath

var _resource_manager: ResourceManager
var _researched: Dictionary = {}  # StringName -> true
var _active_tech_id: StringName = &""
var _days_remaining: int = 0

## No CampaignManager exists yet, so Seafaring's extra gate is wired here
## as a plain settable flag rather than a live query against territory
## state — see TechDefinition's own doc comment. Defaults false, which
## correctly keeps Seafaring locked until a future CampaignManager calls
## set_wales_and_scotland_retaken(true) once recapture state actually
## exists to check.
var _wales_and_scotland_retaken: bool = false

func _ready() -> void:
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	TickManager.day_completed.connect(_on_day_completed)

## Exposed for a future CampaignManager to call once Wales and
## Scotland are both fully retaken — see class doc comment.
func set_wales_and_scotland_retaken(value: bool) -> void:
	_wales_and_scotland_retaken = value

func is_researched(tech_id: StringName) -> bool:
	return _researched.has(tech_id)

func get_researched_techs() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_researched.keys())
	return result

func get_active_tech() -> StringName:
	return _active_tech_id

func get_days_remaining() -> int:
	return _days_remaining

## Whether unit Tier `tier`'s roster is unlocked. Tier 0 is the
## free starting roster (design doc: "this *is* the 'Free Ammo' tier") and is
## always considered unlocked, with no tech node to check.
func is_unit_tier_unlocked(tier: int) -> bool:
	if tier <= 0:
		return true
	return is_researched(StringName("unit_tier_%d" % tier))

## Whether wall Tier `tier` (0=Wooden, 1=Brick, 2=Concrete) is
## unlocked. Wooden is the baseline and always unlocked, with no tech node
## to check — mirrors is_unit_tier_unlocked()'s tier-0 rule.
func is_wall_tier_unlocked(tier: int) -> bool:
	if tier <= 0:
		return true
	for definition in TechCatalog.get_all_definitions():
		if definition.unlock_type == GameEnums.TechUnlockType.WALL_TIER and definition.unlock_value == tier:
			return is_researched(definition.tech_id)
	return false

## Returns "" if `tech_id` can legally start research right now, or a
## human-readable rejection reason otherwise — mirrors
## BuildingManager.get_placement_error()'s "queryable without side effects"
## pattern so a future Tech Tree screen can preview legality.
func get_research_error(tech_id: StringName) -> String:
	var definition := TechCatalog.get_definition(tech_id)
	if not definition:
		return "Unknown technology."
	if is_researched(tech_id):
		return "%s is already researched." % definition.display_name
	if not _active_tech_id.is_empty():
		var active_definition := TechCatalog.get_definition(_active_tech_id)
		var active_name := active_definition.display_name if active_definition else String(_active_tech_id)
		return "Already researching %s." % active_name
	for prereq_id in definition.prerequisites:
		if not is_researched(prereq_id):
			var prereq_definition := TechCatalog.get_definition(prereq_id)
			var prereq_name := prereq_definition.display_name if prereq_definition else String(prereq_id)
			return "%s requires %s first." % [definition.display_name, prereq_name]
	if definition.requires_wales_and_scotland_retaken and not _wales_and_scotland_retaken:
		return "%s cannot be researched until Wales and Scotland are both fully retaken." % definition.display_name
	if _resource_manager and not _resource_manager.can_afford(definition.cost):
		return "Not enough resources to research %s." % definition.display_name
	return ""

func can_start_research(tech_id: StringName) -> bool:
	return get_research_error(tech_id).is_empty()

## Spends `definition.cost` and begins counting down `research_days` toward
## `tech_id`. Returns whether research actually started; emits
## research_rejected with a reason otherwise rather than failing silently.
func start_research(tech_id: StringName) -> bool:
	var error := get_research_error(tech_id)
	if not error.is_empty():
		research_rejected.emit(tech_id, error)
		return false

	var definition := TechCatalog.get_definition(tech_id)
	if _resource_manager:
		_resource_manager.spend(definition.cost)

	_active_tech_id = tech_id
	_days_remaining = maxi(definition.research_days, 1)
	research_started.emit(tech_id)
	research_progress_changed.emit(tech_id, _days_remaining, definition.research_days)
	return true

func _on_day_completed(_day_number: int) -> void:
	if _active_tech_id.is_empty():
		return

	_days_remaining -= 1
	if _days_remaining > 0:
		var definition := TechCatalog.get_definition(_active_tech_id)
		research_progress_changed.emit(_active_tech_id, _days_remaining, definition.research_days)
		return

	var finished_id := _active_tech_id
	_researched[finished_id] = true
	_active_tech_id = &""
	_days_remaining = 0
	tech_researched.emit(finished_id)

## Exposed for SaveLoadManager — researched set, in-progress node, and its
## remaining days are the only state this class owns; TechCatalog itself
## is static seed data, same as BuildingCatalog, and never needs saving.
func get_save_state() -> Dictionary:
	return {
		"researched": get_researched_techs(),
		"active_tech_id": _active_tech_id,
		"days_remaining": _days_remaining,
	}

func load_save_state(state: Dictionary) -> void:
	_researched.clear()
	for tech_id in state.get("researched", []):
		_researched[tech_id] = true
	_active_tech_id = state.get("active_tech_id", &"")
	_days_remaining = state.get("days_remaining", 0)
