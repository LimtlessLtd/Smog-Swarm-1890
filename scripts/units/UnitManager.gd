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
## Trained at any building with BuildingDefinition.can_train_units — in
## practice just the Garrison today (the design doc's own "Barracks" is this
## same building; no separate BuildingType exists for it — see Phase 2.3's
## "Unlocks major wall fortifications and Barracks for unit recruitment").
## **Training now takes real time** (user report, superseding this class's
## earlier "instant once paid" decision): resources are spent immediately on
## a validated request, but the unit itself isn't registered — and
## unit_trained doesn't fire — until _process_pending_training() below
## finishes counting down _training_days(), mirroring
## BuildingManager.place_building()'s own queue exactly (see that function's
## doc comment for the full reasoning, including the still-open save/load gap).
##
## Phase 5.6's Retrain order lives here too (a lifecycle operation — it
## swaps `UnitInstance.definition` and rescales HP, the same kind of thing
## train_unit()/remove_unit() already do) even though the rest of 5.6
## (movement/patrol/garrison/rally-point automation) lives in the new
## sibling UnitOrderController. Rally points themselves (also 5.6) are
## tracked here rather than there: a rally point is per-TRAINING-BUILDING
## configuration, set once and read every time train_unit() runs, which
## fits this class's existing "who exists and how they came to" role better
## than UnitOrderController's per-tick movement loop.
##
## Combat HP loss/death is real now too (CombatCoordinator, Phase
## 5.4/5.9/5.10's live combat trigger, calls CombatEngine and — on a unit
## reaching 0 HP — remove_unit() below), but that whole path lives outside
## this class: UnitManager itself still never references CombatEngine or
## CombatCoordinator, same separation-of-concerns split described above.
##
## Deliberately NOT here yet, each blocked on a system that doesn't exist:
##   - Morale/veterancy (Phase 5.7).
##   - Starvation exemption bookkeeping (design doc, decided: units are
##     exempt) — moot for now since nothing feeds them Food upkeep at all;
##     see UnitDefinition's own doc comment on why Food isn't modeled here.

signal unit_trained(instance: UnitInstance)
signal unit_removed(instance: UnitInstance)
signal training_rejected(unit_type: GameEnums.UnitType, coord: Vector2i, reason: String)
signal unit_retrained(instance: UnitInstance)
signal retrain_rejected(instance: UnitInstance, new_type: GameEnums.UnitType, reason: String)
## User report ("training units... should take some amount of time") —
## unit_trained/unit_retrained (above) now only fire once a queued job
## actually finishes; these fire the moment it's accepted and paid for.
signal training_started(unit_type: GameEnums.UnitType, coord: Vector2i, days: int)
signal retrain_started(instance: UnitInstance, new_type: GameEnums.UnitType, days: int)

## Design doc: "50% of that unit's normal training cost (exact % subject to
## balancing later)" — a placeholder number, not an architecture decision,
## same framing as every other balancing constant in this project.
const RETRAIN_COST_FRACTION: float = 0.5

## User report ("training units... should take some amount of time") —
## tier-derived duration, same "placeholder balancing number" framing
## RETRAIN_COST_FRACTION above already uses. Tier is already this project's
## own proxy for "how advanced a unit is" (T0 Melee/Ranged/Special through
## T5), so it doubles as a training-time proxy too rather than inventing a
## second per-unit cost field just for this.
const _TRAINING_DAYS_PER_TIER: int = 1
const _MAX_TRAINING_DAYS: int = 4
const _RETRAIN_DAYS_FRACTION: float = 0.5  ## Same halving RETRAIN_COST_FRACTION already applies to resource cost — retraining an existing veteran is faster than training a recruit from nothing, not just cheaper.

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var resource_manager_path: NodePath
@export var tech_manager_path: NodePath  ## Optional — unset gracefully treats every tier as unlocked, same "optional manager reference" convention DiscontentManager/TechManager references use elsewhere.

## Training-building hex -> rally point hex (design doc 5.6: "rally point
## on newly-trained units"). Independent of which units currently exist —
## read by train_unit() every time a fresh unit is registered, not tied to
## any single unit's lifetime.
var _rally_points: Dictionary = {}  # Vector2i -> Vector2i

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _instances: Array[UnitInstance] = []
var _next_id: int = 1
## Paid-for training/retraining not yet finished — see train_unit()/
## retrain_unit() for how an entry is added, _process_pending_training()/
## _process_pending_retrain() for how it's ticked down and completed.
## training: {unit_type, coord, days_remaining}
## retrain: {instance, new_type, days_remaining}
## Same known gap as BuildingManager's own equivalent queues: not yet part
## of the save/load round trip (flagged there, not repeated per-file).
var _pending_training: Array[Dictionary] = []
var _pending_retrain: Array[Dictionary] = []

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

## User request (playtest round 5): "there should be a visible unit
## building queue so that we can see how long is remaining on units under
## construction and how many units of what types we have under
## construction." Exposes the SAME `_pending_training` entries
## `_process_pending_training()` itself ticks down and completes — a UI
## reading this can't drift from what's actually queued. Duplicated (same
## "caller gets its own copy" convention `get_all_units()` above already
## follows) so a caller can't accidentally mutate the real queue by editing
## what it reads.
func get_pending_training() -> Array[Dictionary]:
	return _pending_training.duplicate(true)

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
	if not _get_training_building(coord):
		return "%s can only be trained at a building that trains units (a Garrison)." % definition.display_name
	if _resource_manager and not _resource_manager.can_afford(definition.training_cost):
		return "Not enough resources to train %s." % definition.display_name
	return ""

func can_train_unit(unit_type: GameEnums.UnitType, coord: Vector2i) -> bool:
	return get_training_error(unit_type, coord).is_empty()

## Returns `true` once the request is validated, paid for, and queued — NOT
## once the unit actually exists. See this class's own doc comment on why
## training now takes real time; the one real caller
## (UnitCommandController.train_at_selected_building()) never read the
## returned UnitInstance anyway, so `bool` (accepted or not) is all this
## needs to report now.
func train_unit(unit_type: GameEnums.UnitType, coord: Vector2i) -> bool:
	var error := get_training_error(unit_type, coord)
	if not error.is_empty():
		training_rejected.emit(unit_type, coord, error)
		return false

	var definition := UnitCatalog.get_definition(unit_type)
	if _resource_manager:
		_resource_manager.spend(definition.training_cost)

	var days := mini(definition.tier * _TRAINING_DAYS_PER_TIER + _TRAINING_DAYS_PER_TIER, _MAX_TRAINING_DAYS)
	_pending_training.append({"unit_type": unit_type, "coord": coord, "days_remaining": days})
	training_started.emit(unit_type, coord, days)
	return true

## Ticks every queued job down by one day, completing (spawning the real
## unit / applying the retrain) anything that reaches zero — mirrors
## BuildingManager._process_pending_construction()'s own shape exactly.
func _process_pending_training() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_training:
		job["days_remaining"] -= 1
		if job["days_remaining"] <= 0:
			_complete_training(job["unit_type"], job["coord"])
		else:
			still_pending.append(job)
	_pending_training = still_pending

func _complete_training(unit_type: GameEnums.UnitType, coord: Vector2i) -> void:
	var definition := UnitCatalog.get_definition(unit_type)
	var training_building := _get_training_building(coord)
	var spawn_position := _spawn_local_position(coord, training_building.local_position if training_building else Vector2.ZERO)
	var instance := _register_instance(definition, coord, _next_id, true, -1.0, GameEnums.UnitOrderType.HOLD, Vector2i.ZERO, [], 0, spawn_position)
	# Design doc 5.6: "rally point on newly-trained units" — a fresh unit
	# with no rally point registered for its training building just stays
	# put (order defaults to HOLD, see UnitInstance). UnitOrderController's
	# own movement tick (not called from here — see this class's own doc
	# comment on why) picks the MOVE order up the next time it runs.
	if _rally_points.has(coord):
		instance.order = GameEnums.UnitOrderType.MOVE
		instance.move_target = _rally_points[coord]

## Spawn clearance outside a training building's own footprint (user
## report: newly-trained units were rendering stacked exactly on top of the
## Garrison) — just past TacticalHexView.BUILDING_HALF_SIZE's own value so a
## fresh unit doesn't visually overlap the building it just came from.
## Deliberately NOT full pathfinding-aware "nearest walkable point" (this
## project's Phase 5.5 shared pathfinder is a real, larger, still-unbuilt
## system) — a deterministic ring around the training building is a
## reasonable, self-contained approximation for where an "outside the front
## door" spawn should land, same scope as _resolved_building_position()'s
## own ring fallback in TacticalHexView for stacked buildings.
##
## **Drift risk, re-checked this pass (was flagged as a real but not-yet-
## verified risk in prior session notes, not an active bug):** this is a
## hand-copied literal, not a real reference into
## `TacticalHexView.BUILDING_HALF_SIZE` — the same "can silently drift out
## of sync across a future building-box resize" shape `ObstacleRadii.
## BUILDING_RADIUS`'s own doc comment already disclaims (that constant hand-
## copies the same source of truth for the same reason: this project avoids
## const-referencing across class_name scripts). Verified numerically
## against the CURRENT value (`BUILDING_HALF_SIZE` = 20.512, half-diagonal
## ≈ 29.0 post-4x-bump) — 60.0 still clears with a healthy ~2x margin, so
## there is no live bug today. Still hand-copied, so it can drift again the
## next time `BUILDING_HALF_SIZE` is resized — re-check this constant
## whenever that one changes, same as `ObstacleRadii.BUILDING_RADIUS`.
const _SPAWN_CLEARANCE: float = 60.0
const _SPAWN_RING_STEP: float = 24.0  ## Extra radius per already-occupied spawn slot, so several units trained in a row fan out around the building instead of stacking on each other.
const _SPAWN_RING_SLOTS: int = 6

func _spawn_local_position(coord: Vector2i, training_building_position: Vector2) -> Vector2:
	var already_near := 0
	for instance in _instances:
		if instance.hex_coord == coord and instance.local_position.distance_to(training_building_position) < _SPAWN_CLEARANCE + _SPAWN_RING_STEP * 6.0:
			already_near += 1
	var angle := TAU * float(already_near % _SPAWN_RING_SLOTS) / float(_SPAWN_RING_SLOTS)
	var radius := _SPAWN_CLEARANCE + _SPAWN_RING_STEP * float(already_near / _SPAWN_RING_SLOTS)
	return training_building_position + Vector2(cos(angle), sin(angle)) * radius

func remove_unit(instance: UnitInstance) -> void:
	_instances.erase(instance)
	unit_removed.emit(instance)

func set_rally_point(building_coord: Vector2i, target: Vector2i) -> void:
	_rally_points[building_coord] = target

func clear_rally_point(building_coord: Vector2i) -> void:
	_rally_points.erase(building_coord)

func has_rally_point(building_coord: Vector2i) -> bool:
	return _rally_points.has(building_coord)

## Returns `building_coord` itself ("stay put") if no rally point is registered.
func get_rally_point(building_coord: Vector2i) -> Vector2i:
	return _rally_points.get(building_coord, building_coord)

## Design doc Phase 5.4/5.6's Retrain order: converts `instance` in-place to
## `new_type` — same role, a strictly higher tier, unlocked, for
## RETRAIN_COST_FRACTION of `new_type`'s own training cost. Instant (no
## duration), usable anywhere including mid-battle (design doc, decided) —
## this just swaps `definition` and rescales `current_hp`, no cooldown or
## queue of any kind.
##
## Returns "" if `instance` can legally retrain into `new_type` right now,
## or a human-readable rejection reason otherwise — same
## "queryable without side effects" pattern as get_training_error().
func get_retrain_error(instance: UnitInstance, new_type: GameEnums.UnitType) -> String:
	var new_definition := UnitCatalog.get_definition(new_type)
	if not new_definition:
		return "Unknown unit type."
	if not instance.definition:
		return "Unit has no definition to retrain from."
	if new_definition.role != instance.definition.role:
		return "%s can only retrain into another same-role unit." % instance.definition.display_name
	if new_definition.tier <= instance.definition.tier:
		return "Retraining must upgrade to a strictly higher tier."
	if _tech_manager and not _tech_manager.is_unit_tier_unlocked(new_definition.tier):
		return "%s's tier hasn't been researched yet." % new_definition.display_name
	if _resource_manager and not _resource_manager.can_afford(_retrain_cost(new_definition)):
		return "Not enough resources to retrain into %s." % new_definition.display_name
	return ""

func can_retrain_unit(instance: UnitInstance, new_type: GameEnums.UnitType) -> bool:
	return get_retrain_error(instance, new_type).is_empty()

## Same "pay upfront, finish later" shape train_unit() now uses. The unit
## keeps fighting/holding/whatever its current order is while retraining is
## in progress (there's no "unavailable" state to model — it just isn't yet
## the new type); unit_retrained fires, and the definition/HP actually
## swap, once _process_pending_retrain() below finishes counting down.
func retrain_unit(instance: UnitInstance, new_type: GameEnums.UnitType) -> bool:
	var error := get_retrain_error(instance, new_type)
	if not error.is_empty():
		retrain_rejected.emit(instance, new_type, error)
		return false

	var new_definition := UnitCatalog.get_definition(new_type)
	if _resource_manager:
		_resource_manager.spend(_retrain_cost(new_definition))

	var days := maxi(1, ceili(float(mini(new_definition.tier * _TRAINING_DAYS_PER_TIER + _TRAINING_DAYS_PER_TIER, _MAX_TRAINING_DAYS)) * _RETRAIN_DAYS_FRACTION))
	_pending_retrain.append({"instance": instance, "new_type": new_type, "days_remaining": days})
	retrain_started.emit(instance, new_type, days)
	return true

func _process_pending_retrain() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_retrain:
		job["days_remaining"] -= 1
		if job["days_remaining"] <= 0:
			_complete_retrain(job["instance"], job["new_type"])
		else:
			still_pending.append(job)
	_pending_retrain = still_pending

func _complete_retrain(instance: UnitInstance, new_type: GameEnums.UnitType) -> void:
	if not _instances.has(instance):
		return  ## The unit was lost in combat while retraining was in progress — nothing left to complete.
	var new_definition := UnitCatalog.get_definition(new_type)
	# Carries over relative damage state rather than a free full heal on
	# retrain — a unit at half health before retraining is at half health
	# (of its NEW, larger max_hp) after, not topped up for free.
	var hp_fraction := instance.current_hp / instance.definition.max_hp if instance.definition.max_hp > 0.0 else 1.0
	instance.definition = new_definition
	instance.current_hp = new_definition.max_hp * hp_fraction
	unit_retrained.emit(instance)

func _retrain_cost(new_definition: UnitDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in new_definition.training_cost:
		cost[resource_type] = float(new_definition.training_cost[resource_type]) * RETRAIN_COST_FRACTION
	return cost

## Shared instance-bookkeeping between a fresh train_unit() (already
## validated/paid above) and load_save_state() (restoring units already paid
## for in a previous session) — same split BuildingManager.place_building()/
## load_save_entries() use around _register_instance().
func _register_instance(definition: UnitDefinition, coord: Vector2i, id: int, advance_next_id: bool, current_hp: float = -1.0, order: GameEnums.UnitOrderType = GameEnums.UnitOrderType.HOLD, move_target: Vector2i = Vector2i.ZERO, patrol_waypoints: Array[Vector2i] = [], kill_count: int = 0, local_position: Vector2 = Vector2.ZERO, move_target_local: Vector2 = Vector2.ZERO, patrol_waypoint_locals: Array[Vector2] = []) -> UnitInstance:
	var instance := UnitInstance.new(definition, coord, id, current_hp)
	instance.order = order
	instance.move_target = move_target
	instance.patrol_waypoints = patrol_waypoints
	instance.kill_count = kill_count
	instance.local_position = local_position
	instance.move_target_local = move_target_local
	instance.patrol_waypoint_locals = patrol_waypoint_locals
	if advance_next_id:
		_next_id = id + 1
	_instances.append(instance)
	unit_trained.emit(instance)
	return instance

## Found alongside a user report that UnitPanelView's training panel was
## popping up for buildings that can't actually train anyone: this
## VALIDATION check had the exact same bug (any Military-ZoC building —
## Watchtower, Ammo Dump, Searchlight Tower too, not just Garrison — used
## to pass here for lookout/logistics/illumination reasons unrelated to
## training) it was just never caught because the only training-capable
## building anyone had actually placed in testing was a Garrison. Gated on
## BuildingDefinition.can_train_units now, same flag/fix as
## UnitCommandController._has_training_building(). Returns the instance
## (not just a bool) so train_unit() can also read its local_position for
## _spawn_local_position() below, rather than a second near-identical query.
func _get_training_building(coord: Vector2i) -> BuildingInstance:
	if not _building_manager:
		return null
	for instance in _building_manager.get_buildings_at(coord):
		if instance.definition.can_train_units:
			return instance
	return null

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
	_process_pending_training()
	_process_pending_retrain()
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
		result.append(UnitSaveEntry.new(instance.definition.unit_type, instance.hex_coord, instance.id, instance.current_hp, instance.order, instance.move_target, instance.patrol_waypoints, instance.kill_count, instance.local_position, instance.move_target_local, instance.patrol_waypoint_locals))
	return result

## Restores trained units from a save (Phase 2.8.2): clears whatever is
## currently tracked, then recreates each entry via _register_instance()
## directly — bypassing train_unit()'s cost/validation, since these units
## already exist and were already paid for. Mirrors
## BuildingManager.load_save_entries() exactly. In-flight movement paths
## (UnitInstance.path) aren't restored — UnitOrderController replans from
## scratch the first time it ticks a MOVE/ATTACK_MOVE/PATROL unit after load.
func load_save_entries(entries: Array[UnitSaveEntry], next_id: int) -> void:
	_instances.clear()
	for entry in entries:
		var definition := UnitCatalog.get_definition(entry.unit_type)
		if definition:
			_register_instance(definition, entry.hex_coord, entry.id, false, entry.current_hp, entry.order, entry.move_target, entry.patrol_waypoints, entry.kill_count, entry.local_position, entry.move_target_local, entry.patrol_waypoint_locals)
	_next_id = next_id

## Exposed for SaveLoadManager (Phase 2.8) — rally-point configuration
## (Phase 5.6), independent of unit instances themselves; see _rally_points'
## own doc comment.
func get_rally_points_save_state() -> Dictionary:
	return _rally_points.duplicate()

func load_rally_points_save_state(state: Dictionary) -> void:
	_rally_points = state.duplicate()
