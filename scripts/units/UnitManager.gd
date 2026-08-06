class_name UnitManager
extends Node

## Runtime owner of every trained UnitInstance (design doc Phase 5.4) — the
## "unit lifecycle" half of that phase: validating training against cost
## (ResourceManager) and the currently unlocked tier
## (TechManager.is_unit_tier_unlocked(), already built and waiting for
## exactly this — see that method's own doc comment), and draining daily
## Gunpowder upkeep (TickManager.day_completed). Mirrors BuildingManager's
## own place/validate/tally-upkeep shape, minus everything specific to
## buildings (daily output, Food/population, Discontent) — units don't
## produce a daily yield or house civilians, they're trained once and then
## just cost upkeep until lost.
##
## Deliberately holds no reference to, and is never referenced by,
## CombatEngine (the "resolve an attack" half of Phase 5.4) — CombatEngine
## takes whichever UnitInstance a future caller (Phase 5.6's orders, Phase
## 5.10's siege handoff) passes it directly; it never asks UnitManager for
## one itself, and UnitManager never calls into CombatEngine. Two separate
## concerns, two separate files, zero coupling between them — the same
## "owns neither, only reads/computes from what's passed in" discipline
## HexPathfinder and LogisticsNetwork already follow elsewhere in this
## project, applied here to keep "who exists" and "what happens when they
## fight" from becoming one tangled class.
##
## Trained at any building projecting the MILITARY Zone-of-Control role — in
## practice just the Garrison today (the design doc's own "Barracks" is this
## same building; no separate BuildingType exists for it — see Phase 2.3's
## "Unlocks major wall fortifications and Barracks for unit recruitment").
## Training is instant once paid, no queue/duration — matches
## BuildingManager.place_building()'s own "no construction time" precedent;
## a training duration is future balancing work, not an architecture gap.
##
## Deliberately NOT here yet, each blocked on a system that doesn't exist:
##   - Movement/orders (Phase 5.5's tactical layer, Phase 5.6's
##     UnitOrderController) — a trained unit sits at its training building's
##     hex until those exist.
##   - Combat HP loss/death — CombatEngine has the math, but nothing calls
##     it yet; no siege/attack-move trigger exists to produce a fight.
##   - Morale/veterancy (Phase 5.7), Retrain orders (Phase 5.6).
##   - Starvation exemption bookkeeping (design doc, decided: units are
##     exempt) — moot for now since nothing feeds them Food upkeep at all;
##     see UnitDefinition's own doc comment on why Food isn't modeled here.

signal unit_trained(instance: UnitInstance)
signal unit_removed(instance: UnitInstance)
signal training_rejected(unit_type: GameEnums.UnitType, coord: Vector2i, reason: String)

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var resource_manager_path: NodePath
@export var tech_manager_path: NodePath  ## Optional — unset gracefully treats every tier as unlocked, same "optional manager reference" convention DiscontentManager/TechManager references use elsewhere.

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _instances: Array[UnitInstance] = []
var _next_id: int = 1

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	TickManager.day_completed.connect(_on_day_completed)

func get_all_units() -> Array[UnitInstance]:
	return _instances.duplicate()

func get_units_at(coord: Vector2i) -> Array[UnitInstance]:
	var result: Array[UnitInstance] = []
	for instance in _instances:
		if instance.hex_coord == coord:
			result.append(instance)
	return result

## Exposed for SaveLoadManager (Phase 2.8) — the next id a freshly-trained
## unit would get, mirrors BuildingManager.get_next_id().
func get_next_id() -> int:
	return _next_id

## Returns "" if `unit_type` can legally be trained at `coord` right now, or
## a human-readable rejection reason otherwise — mirrors
## BuildingManager.get_placement_error()'s "queryable without side effects" pattern.
func get_training_error(unit_type: GameEnums.UnitType, coord: Vector2i) -> String:
	var definition := UnitCatalog.get_definition(unit_type)
	if not definition:
		return "Unknown unit type."
	if _tech_manager and not _tech_manager.is_unit_tier_unlocked(definition.tier):
		return "%s's tier hasn't been researched yet." % definition.display_name
	if not _hex_grid_map:
		return "No hex grid map wired to UnitManager."
	if not _hex_grid_map.has_cell(coord):
		return "%s is outside the map." % coord
	if not _has_military_zoc_source(coord):
		return "%s can only be trained at a building projecting Military Zone of Control (a Garrison)." % definition.display_name
	if _resource_manager and not _resource_manager.can_afford(definition.training_cost):
		return "Not enough resources to train %s." % definition.display_name
	return ""

func can_train_unit(unit_type: GameEnums.UnitType, coord: Vector2i) -> bool:
	return get_training_error(unit_type, coord).is_empty()

func train_unit(unit_type: GameEnums.UnitType, coord: Vector2i) -> UnitInstance:
	var error := get_training_error(unit_type, coord)
	if not error.is_empty():
		training_rejected.emit(unit_type, coord, error)
		return null

	var definition := UnitCatalog.get_definition(unit_type)
	if _resource_manager:
		_resource_manager.spend(definition.training_cost)

	return _register_instance(definition, coord, _next_id, true)

func remove_unit(instance: UnitInstance) -> void:
	_instances.erase(instance)
	unit_removed.emit(instance)

## Shared instance-bookkeeping between a fresh train_unit() (already
## validated/paid above) and load_save_state() (restoring units already paid
## for in a previous session) — same split BuildingManager.place_building()/
## load_save_entries() use around _register_instance().
func _register_instance(definition: UnitDefinition, coord: Vector2i, id: int, advance_next_id: bool, current_hp: float = -1.0) -> UnitInstance:
	var instance := UnitInstance.new(definition, coord, id, current_hp)
	if advance_next_id:
		_next_id = id + 1
	_instances.append(instance)
	unit_trained.emit(instance)
	return instance

func _has_military_zoc_source(coord: Vector2i) -> bool:
	if not _building_manager:
		return false
	for instance in _building_manager.get_buildings_at(coord):
		if instance.definition.zoc_roles.has(GameEnums.ZoneOfControlType.MILITARY):
			return true
	return false

## Daily Gunpowder upkeep tally (UnitDefinition.daily_upkeep, only nonzero
## for requires_gunpowder units) — ResourceManager.apply_daily_flow() with
## an empty `produced` dict, since units generate no daily output of their
## own. Clamps at 0 (not negative) and emits ResourceManager's own
## upkeep_shortfall the same way a building's unpaid upkeep would; nothing
## about the Gunpowder-depletion combat penalty (UnitDefinition's own doc
## comment) is computed here — that's CombatEngine's job at attack time,
## reading the stockpile fresh rather than caching a "shortfall happened"
## flag from today's tally.
func _on_day_completed(_day_number: int) -> void:
	if not _resource_manager or _instances.is_empty():
		return
	var consumed: Dictionary = {}
	for instance in _instances:
		for resource_type in instance.definition.daily_upkeep:
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(instance.definition.daily_upkeep[resource_type])
	if not consumed.is_empty():
		_resource_manager.apply_daily_flow(consumed, {})

## Exposed for SaveLoadManager (Phase 2.8) — mirrors
## BuildingManager.get_save_entries()'s shape via UnitSaveEntry.
func get_save_entries() -> Array[UnitSaveEntry]:
	var result: Array[UnitSaveEntry] = []
	for instance in _instances:
		result.append(UnitSaveEntry.new(instance.definition.unit_type, instance.hex_coord, instance.id, instance.current_hp))
	return result

## Restores trained units from a save (Phase 2.8.2): clears whatever is
## currently tracked, then recreates each entry via _register_instance()
## directly — bypassing train_unit()'s cost/validation, since these units
## already exist and were already paid for. Mirrors
## BuildingManager.load_save_entries() exactly.
func load_save_entries(entries: Array[UnitSaveEntry], next_id: int) -> void:
	_instances.clear()
	for entry in entries:
		var definition := UnitCatalog.get_definition(entry.unit_type)
		if definition:
			_register_instance(definition, entry.hex_coord, entry.id, false, entry.current_hp)
	_next_id = next_id
