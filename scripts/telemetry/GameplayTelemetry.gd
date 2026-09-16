extends Node

## Gameplay telemetry: what happened to the player over a run, recorded from the
## managers' existing public signals and getters. Evidence for
## PLAYER_EXPERIENCE.md's acceptance criteria and boring failure modes, never a
## score — GAME_HEALTH.md states are judged by a reader, not computed from these
## numbers, and no number here has a "better" direction on its own.
##
## Deliberately has no class_name (a new one leaves
## .godot/global_script_class_cache.cfg stale for every other script) and is not
## in Main.tscn: a scenario or harness preloads it and calls attach(). Nothing in
## the game reads it, so it cannot change what it measures.
##
## Timestamps are game-seconds since attach (`TickManager.current_day` and
## `elapsed_in_day`), so a run driven at a fixed delta is reproducible.
##
## Not measured, because no mechanic exists to measure (stated in the output
## under "unmeasurable" so a missing number is not mistaken for a zero):
##  - logistics utilisation: no throughput model (design_doc.md §2.2 unbuilt).
##  - player response time / active decisions: needs a human input stream; the
##    AgentHarness exposes rendered UI only.

const _SAMPLE_RADIUS_HEXES: int = 3  ## Territory-cleared ring around the start hex; the opening's playable neighbourhood.

var _buildings: BuildingManager
var _units: UnitManager
var _hordes: HordeManager
var _infestation: InfestationManager
var _resources: ResourceManager
var _tech: TechManager
var _walls: WallManager
var _fog: FogOfWarManager
var _combat: CombatCoordinator
var _settlements: SettlementFoundingController
var _defeat: DefeatConditionMonitor

var _start_hexes: Array[Vector2i] = []
var _origin_seconds: float = 0.0

var _counters: Dictionary = {}
var _firsts: Dictionary = {}            ## event name -> game-seconds of first occurrence.
var _events: Array[Dictionary] = []     ## Sparse timeline of events worth reading in order.
var _daily: Array[Dictionary] = []
var _shortfalls: Dictionary = {}        ## resource name -> shortfall event count.
var _building_types_placed: Dictionary = {}
var _engagement_days: Dictionary = {}
var _horde_first_visible: Dictionary = {}   ## horde id -> seconds.
var _horde_first_contact: Dictionary = {}   ## horde id -> seconds; contact = standing on a player building's hex.
var _action_days: Dictionary = {}           ## day -> true when a player-initiated action was accepted.


func attach(main: Node) -> void:
	_buildings = main.get_node("BuildingManager")
	_units = main.get_node("UnitManager")
	_hordes = main.get_node("HordeManager")
	_infestation = main.get_node("InfestationManager")
	_resources = main.get_node("ResourceManager")
	_tech = main.get_node("TechManager")
	_walls = main.get_node("WallManager")
	_fog = main.get_node("FogOfWarManager")
	_combat = main.get_node("CombatCoordinator")
	_settlements = main.get_node("SettlementFoundingController")
	_defeat = main.get_node("DefeatConditionMonitor")

	_start_hexes = _buildings.get_starting_settlement_hexes()
	_origin_seconds = now_seconds()

	_buildings.construction_started.connect(func(building_type: GameEnums.BuildingType, coord: Vector2i, _days: int) -> void:
		_count("buildings_placed")
		_building_types_placed[BuildingCatalog.get_definition(building_type).display_name] = true
		_mark_action()
		if not _start_hexes.has(coord):
			_first("first_building_outside_start_hex"))
	_buildings.placement_rejected.connect(func(_t: GameEnums.BuildingType, _c: Vector2i, reason: String) -> void:
		_count("placements_rejected")
		_event("placement_rejected", reason))
	_buildings.building_construction_completed.connect(func(instance: BuildingInstance) -> void:
		_count("buildings_completed")
		_first("first_building_completed", instance.definition.display_name))
	_buildings.building_damaged.connect(func(_i: BuildingInstance, amount: float) -> void:
		_count("building_damage_events")
		_add("building_damage_total", amount)
		_first("first_building_damaged"))
	_buildings.building_ruined.connect(func(instance: BuildingInstance, _lost: int) -> void:
		_count("buildings_ruined")
		_event("building_ruined", "%s at %s" % [instance.definition.display_name, instance.hex_coord]))
	_buildings.building_repaired.connect(func(_i: BuildingInstance) -> void: _count("buildings_repaired"))
	_buildings.building_powered_down.connect(func(_i: BuildingInstance) -> void:
		_count("buildings_powered_down")
		_mark_action())

	_units.training_started.connect(func(_t: GameEnums.UnitType, _c: Vector2i, _d: int) -> void: _mark_action())
	_units.unit_trained.connect(func(instance: UnitInstance) -> void:
		_count("units_trained")
		_first("first_unit_trained", instance.definition.display_name))
	_units.unit_removed.connect(func(instance: UnitInstance) -> void:
		_count("units_removed")
		_event("unit_removed", "%s at %s" % [instance.definition.display_name, instance.hex_coord]))

	_combat.engagement_resolved.connect(func(_u: UnitInstance, _h: Horde, _r: Dictionary) -> void:
		_count("engagements")
		_engagement_days[TickManager.current_day] = true
		_first("first_engagement"))

	_hordes.horde_spawned.connect(func(horde: Horde) -> void:
		_count("hordes_spawned")
		_add("zombies_spawned_in_hordes", float(horde.size)))
	_hordes.horde_moved.connect(_on_horde_moved)

	_infestation.band_changed.connect(func(coord: Vector2i, band: GameEnums.InfestationBand) -> void:
		if band == GameEnums.InfestationBand.CLEARED:
			_count("hexes_became_cleared")
			_event("hex_cleared", str(coord)))
	_infestation.day_simulated.connect(func(_bred: int, exported_hordes: int, exported_zombies: int) -> void:
		_add("exported_hordes", float(exported_hordes))
		_add("exported_zombies", float(exported_zombies)))

	_resources.upkeep_shortfall.connect(func(resource_type: GameEnums.ResourceType, _amount: float) -> void:
		var key := ResourceVisuals.display_name(resource_type)
		_shortfalls[key] = int(_shortfalls.get(key, 0)) + 1)

	_tech.research_started.connect(func(_id: StringName) -> void: _mark_action())
	_tech.tech_researched.connect(func(tech_id: StringName) -> void:
		_count("techs_researched")
		_event("tech_researched", String(tech_id)))

	_walls.wall_segment_placed.connect(func(_s: WallSegment) -> void: _count("wall_pieces_placed"))
	_walls.wall_segment_damaged.connect(func(_s: WallSegment, amount: float) -> void:
		_count("wall_damage_events")
		_add("wall_damage_total", amount)
		_first("first_wall_damaged"))
	_walls.wall_segment_breached.connect(func(_s: WallSegment) -> void:
		_count("wall_breaches")
		_first("first_wall_breach"))

	_settlements.settlement_founded.connect(func(coord: Vector2i) -> void:
		_count("settlements_founded")
		_event("settlement_founded", str(coord)))
	_settlements.settlement_abandoned.connect(func(coord: Vector2i) -> void:
		_count("settlements_abandoned")
		_event("settlement_abandoned", str(coord)))

	_defeat.defeat_risk_changed.connect(func(at_risk: bool, reasons: Array) -> void:
		_event("defeat_risk" if at_risk else "defeat_risk_cleared", ", ".join(reasons)))
	_defeat.campaign_lost.connect(func(reasons: Array) -> void:
		_first("campaign_lost", ", ".join(reasons)))

	TickManager.day_completed.connect(func(_day: int) -> void: sample_day())


func now_seconds() -> float:
	return float(TickManager.current_day - 1) * TickManager.DAY_LENGTH_SECONDS + TickManager.elapsed_in_day


func elapsed() -> float:
	return now_seconds() - _origin_seconds


## Also called by the scenario on its own step when it wants a horde's
## visibility tracked between hex crossings.
func observe_hordes() -> void:
	for horde: Horde in _hordes.get_all_hordes():
		if not _horde_first_visible.has(horde.id) and _fog.is_visible(horde.hex_coord):
			_horde_first_visible[horde.id] = elapsed()


func _on_horde_moved(horde: Horde, _from: Vector2i, to_coord: Vector2i) -> void:
	observe_hordes()
	if _horde_first_contact.has(horde.id):
		return
	for building: BuildingInstance in _buildings.get_buildings_at(to_coord):
		if not building.is_ruined:
			_horde_first_contact[horde.id] = elapsed()
			_event("horde_contact", "horde %d (%d) at %s" % [horde.id, horde.size, to_coord])
			_first("first_horde_contact")
			return


func sample_day() -> void:
	var army := 0
	for unit: UnitInstance in _units.get_all_units():
		if not unit.is_destroyed():
			army += 1
	var standing := 0
	var ruined := 0
	for building: BuildingInstance in _buildings.get_all_buildings():
		if building.is_ruined:
			ruined += 1
		else:
			standing += 1
	var horde_zombies := 0
	var nearest := -1
	for horde: Horde in _hordes.get_all_hordes():
		horde_zombies += horde.size
		var d := _distance_to_player(horde.hex_coord)
		if d >= 0 and (nearest < 0 or d < nearest):
			nearest = d
	var cleared := 0
	var ring_total := 0
	if not _start_hexes.is_empty():
		for coord in HexCoord.hex_disk(_start_hexes[0], _SAMPLE_RADIUS_HEXES):
			ring_total += 1
			if _infestation.is_cleared(coord):
				cleared += 1
	var stock := {}
	for resource_type in [GameEnums.ResourceType.WOOD, GameEnums.ResourceType.FOOD, GameEnums.ResourceType.BRICKS,
			GameEnums.ResourceType.IRON, GameEnums.ResourceType.GUNPOWDER, GameEnums.ResourceType.RESEARCH_POINTS]:
		stock[ResourceVisuals.display_name(resource_type)] = snappedf(_resources.get_amount(resource_type), 0.1)
	_daily.append({
		"day": TickManager.current_day,
		"army": army,
		"buildings_standing": standing,
		"buildings_ruined": ruined,
		"hordes": _hordes.get_all_hordes().size(),
		"horde_zombies": horde_zombies,
		"nearest_horde_hexes": nearest,
		"cleared_hexes_within_%d" % _SAMPLE_RADIUS_HEXES: "%d/%d" % [cleared, ring_total],
		"stockpile": stock,
	})


func report() -> Dictionary:
	var warnings: Array[float] = []
	for id in _horde_first_contact:
		if _horde_first_visible.has(id):
			warnings.append(float(_horde_first_contact[id]) - float(_horde_first_visible[id]))
	var army_sum := 0.0
	var idle_days := 0
	for sample: Dictionary in _daily:
		army_sum += float(sample["army"])
		if not _action_days.has(int(sample["day"]) - 1):
			idle_days += 1
	var catalog_size := BuildingCatalog.get_all_definitions().size()
	return {
		"elapsed_game_seconds": elapsed(),
		"elapsed_days": elapsed() / TickManager.DAY_LENGTH_SECONDS,
		"real_minutes_at_default_speed": elapsed() / TickManager.SPEED_MULTIPLIERS[1] / 60.0,
		"counters": _counters,
		"firsts_game_seconds": _firsts,
		"days_with_engagements": _engagement_days.size(),
		"days_without_player_action": idle_days,
		"mean_army_size": army_sum / maxf(1.0, float(_daily.size())),
		"building_types_used": "%d/%d" % [_building_types_placed.size(), catalog_size],
		"resource_shortfall_events": _shortfalls,
		"horde_warning_seconds": warnings,
		"hordes_seen_before_contact": warnings.size(),
		"hordes_that_made_contact": _horde_first_contact.size(),
		"daily": _daily,
		"events": _events,
		"unmeasurable": {
			"logistics_utilisation": "no throughput model exists (design_doc.md §2.2 unbuilt)",
			"player_response_time": "needs a human input stream",
		},
	}


func _distance_to_player(coord: Vector2i) -> int:
	var nearest := -1
	for building: BuildingInstance in _buildings.get_all_buildings():
		if building.is_ruined:
			continue
		var d := HexCoord.distance(coord, building.hex_coord)
		if nearest < 0 or d < nearest:
			nearest = d
	return nearest


func _mark_action() -> void:
	_action_days[TickManager.current_day] = true


func _count(key: String) -> void:
	_counters[key] = int(_counters.get(key, 0)) + 1


func _add(key: String, amount: float) -> void:
	_counters[key] = float(_counters.get(key, 0.0)) + amount


func _first(key: String, detail: String = "") -> void:
	if _firsts.has(key):
		return
	_firsts[key] = elapsed()
	_event(key, detail)


func _event(kind: String, detail: String) -> void:
	_events.append({"t": snappedf(elapsed(), 1.0), "day": TickManager.current_day, "kind": kind, "detail": detail})
