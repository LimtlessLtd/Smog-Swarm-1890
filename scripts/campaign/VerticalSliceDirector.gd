class_name VerticalSliceDirector
extends Node

## Runs the vertical slice (VerticalSliceConfig) when GameLaunchState asks for one,
## and does nothing otherwise. It owns the slice's script — the start, the moment
## the horde leaves the moor, the objectives and their progress, the dispatches
## that tell the player what just changed, and when the slice is over. It owns no
## rule of the game: every threat, fight and clear is the real simulation, and the
## director only watches its signals.
##
## Dispatches are written from what the simulation reports, not from a timeline:
## "it has seen your lamps" is said because HordeManager.horde_attracted fired with
## KIND_LIGHT, so the words and the mechanic cannot drift apart.

signal objectives_changed
## A short headline, a sentence or two of what it means, where to look (a world
## position and the camera zoom that frames it — hex scale for a hex, wall scale
## for a siege), and whether it is urgent enough to stop the clock.
signal dispatch(title: String, body: String, world: Vector2, zoom: float, urgent: bool)

## Camera zooms a dispatch asks for (CameraController.set_zoom_level): the start and
## its ring, and close enough on a wall piece that a bow's 200 m reads as ~100 px.
const ZOOM_HEX_SCALE: float = 0.3
const ZOOM_WALL_SCALE: float = 5.0
## &"success", &"defeat" or &"time".
signal slice_finished(outcome: StringName)

const OBJECTIVE_CLEAR := &"clear"
const OBJECTIVE_HORDE := &"horde"
const OBJECTIVE_FARM := &"farm"

## Game-seconds between objective re-evaluations. Progress bars move in whole
## zombies, and one evaluation reads a few Dictionary entries.
const EVALUATE_INTERVAL_SECONDS: float = 2.0
## Game-seconds between the last required objective completing and the slice
## declaring itself over, so the player sees the moment before the debrief covers it.
const FINISH_DELAY_SECONDS: float = 40.0

@export var building_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var resource_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var infestation_manager_path: NodePath
@export var horde_manager_path: NodePath

var _buildings: BuildingManager
var _units: UnitManager
var _resources: ResourceManager
var _walls: WallManager
var _infestation: InfestationManager
var _hordes: HordeManager

var _active: bool = false
var _elapsed: float = 0.0
var _evaluate_timer: float = 0.0
var _horde: Horde = null
var _horde_released: bool = false
var _horde_ever_attracted: bool = false
var _dawns_since_release: int = 0
var _finished: bool = false
var _finish_countdown: float = -1.0
var _target_seeded: int = 0
var _target_threshold: int = 0
var _objectives: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameLaunchState.is_vertical_slice():
		return
	if building_manager_path:
		_buildings = get_node_or_null(building_manager_path) as BuildingManager
	if unit_manager_path:
		_units = get_node_or_null(unit_manager_path) as UnitManager
	if resource_manager_path:
		_resources = get_node_or_null(resource_manager_path) as ResourceManager
	if wall_manager_path:
		_walls = get_node_or_null(wall_manager_path) as WallManager
	if infestation_manager_path:
		_infestation = get_node_or_null(infestation_manager_path) as InfestationManager
	if horde_manager_path:
		_hordes = get_node_or_null(horde_manager_path) as HordeManager
	if not _buildings or not _units or not _resources or not _infestation or not _hordes:
		push_warning("VerticalSliceDirector: a manager is not wired; the slice will not run.")
		return
	var start_hexes := _buildings.get_starting_settlement_hexes()
	if start_hexes.is_empty() or start_hexes[0] != VerticalSliceConfig.START_HEX:
		push_warning("VerticalSliceDirector: the settlement was not seeded on VerticalSliceConfig.START_HEX; the slice will not run.")
		return
	VerticalSliceSetup.apply(_buildings, _units, _resources, _walls)
	_active = true
	_target_seeded = _infestation.resident_count_at(VerticalSliceConfig.TARGET_HEX)
	_target_threshold = int(ceil(InfestationManager.CLEARED_BELOW / 100.0 * float(_infestation.capacity_at(VerticalSliceConfig.TARGET_HEX))))

	_hordes.horde_attracted.connect(_on_horde_attracted)
	_hordes.horde_lost_attraction.connect(_on_horde_lost_attraction)
	_hordes.horde_siege_started.connect(_on_horde_siege_started)
	_hordes.horde_removed.connect(_on_horde_removed)
	_infestation.band_changed.connect(_on_band_changed)
	_buildings.building_ruined.connect(_on_building_ruined)
	if _walls:
		_walls.wall_segment_breached.connect(_on_wall_breached)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)

	_objectives = [
		{"id": OBJECTIVE_CLEAR, "title": "Clear %s" % VerticalSliceConfig.TARGET_NAME, "detail": "", "progress": 0.0, "state": &"active", "required": true},
	]
	_refresh_clear_objective()
	objectives_changed.emit()
	# Deferred so the HUD, connected in its own _ready() after this one, hears it.
	call_deferred("_announce_start")


func is_active() -> bool:
	return _active

func get_elapsed_seconds() -> float:
	return _elapsed

func get_objectives() -> Array[Dictionary]:
	return _objectives.duplicate(true)

## The slice's horde once it has left the moor, or null before and after.
func get_horde() -> Horde:
	return _horde

func has_released_horde() -> bool:
	return _horde_released

func get_target_seeded() -> int:
	return _target_seeded

func get_target_threshold() -> int:
	return _target_threshold

func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	if not _active or _finished:
		return
	_elapsed += delta
	if not _horde_released and _elapsed >= VerticalSliceConfig.HORDE_RELEASE_SECONDS:
		_release_horde()
	_evaluate_timer += delta
	if _evaluate_timer >= EVALUATE_INTERVAL_SECONDS:
		_evaluate_timer = 0.0
		_evaluate()
	if _finish_countdown >= 0.0:
		_finish_countdown -= delta
		if _finish_countdown <= 0.0:
			_finish(&"success")
			return
	if _elapsed >= VerticalSliceConfig.TIME_LIMIT_SECONDS:
		_finish(&"time")


func _announce_start() -> void:
	dispatch.emit("Manchester, the southern edge",
		"%s, south-west beyond the wall, is open ground for farms and coal under %d of the dead. Clear it: send the squad onto the hex and they fight whatever reaches them. %d must fall before it counts as cleared." % [VerticalSliceConfig.TARGET_NAME.capitalize(), _target_seeded, _target_seeded - _target_threshold],
		HexCoord.axial_to_world(VerticalSliceConfig.TARGET_HEX), ZOOM_HEX_SCALE, false)


func _release_horde() -> void:
	_horde_released = true
	var moved := _infestation.condense_defenders(VerticalSliceConfig.HORDE_SOURCE_HEX, VerticalSliceConfig.HORDE_SIZE)
	var at_source := _hordes.get_hordes_at(VerticalSliceConfig.HORDE_SOURCE_HEX)
	if moved <= 0 or at_source.is_empty():
		push_warning("VerticalSliceDirector: the horde source had no residents to move.")
		return
	_horde = at_source[0]
	if not _hordes.send_wandering_toward(_horde, VerticalSliceConfig.HORDE_DRIFT_HEX):
		push_warning("VerticalSliceDirector: no horde route from the source to the drift hex.")
	_objectives.append({"id": OBJECTIVE_HORDE, "title": "Deal with the horde", "detail": "", "progress": 0.0, "state": &"active", "required": true})
	objectives_changed.emit()
	var lamps := _lit_lamps_at_start()
	dispatch.emit("%d dead on the move" % _horde.size,
		"Scouts on the moor to the %s: a horde of %d has left its ground %d hexes out and is drifting along the moor toward the town. Nothing of yours reaches it yet. At nightfall your %d lit Watchtower%s will be seen from %d hex%s, and within a hex it will hear the Brickworks. Meet it at the wall with archers, or be dark and quiet when it passes." % [
			_bearing_word(VerticalSliceConfig.START_HEX, _horde.hex_coord), _horde.size, HexCoord.distance(VerticalSliceConfig.START_HEX, _horde.hex_coord),
			lamps, "" if lamps == 1 else "s", NoiseManager.light_reach_hexes(lamps, HordeManager.ATTRACTION_THRESHOLD), "" if NoiseManager.light_reach_hexes(lamps, HordeManager.ATTRACTION_THRESHOLD) == 1 else "es"],
		_horde_world(_horde), ZOOM_HEX_SCALE, true)


func _evaluate() -> void:
	_refresh_clear_objective()
	_refresh_horde_objective()
	_refresh_farm_objective()
	objectives_changed.emit()
	if _finish_countdown < 0.0 and _all_required_done():
		_finish_countdown = FINISH_DELAY_SECONDS
		dispatch.emit("The ground is yours", "%s is cleared, claimed and farmed, and the horde is dealt with. The debrief follows." % VerticalSliceConfig.TARGET_NAME.capitalize(), HexCoord.axial_to_world(VerticalSliceConfig.TARGET_HEX), ZOOM_HEX_SCALE, false)


func _refresh_clear_objective() -> void:
	var objective := _objective(OBJECTIVE_CLEAR)
	if objective.is_empty() or objective["state"] != &"active":
		return
	var remaining := _infestation.zombie_count_at(VerticalSliceConfig.TARGET_HEX)
	var span := maxi(1, _target_seeded - _target_threshold)
	objective["progress"] = clampf(float(_target_seeded - remaining) / float(span), 0.0, 1.0)
	objective["detail"] = "%d dead remain — cleared below %d" % [remaining, _target_threshold]
	if _infestation.is_cleared(VerticalSliceConfig.TARGET_HEX):
		_complete_clear()


func _complete_clear() -> void:
	var objective := _objective(OBJECTIVE_CLEAR)
	if objective.is_empty() or objective["state"] != &"active":
		return
	objective["state"] = &"done"
	objective["progress"] = 1.0
	objective["detail"] = "Cleared — build rights on the whole hex"
	# Required: taking ground is only half of expansion (EXP-2, "clearing yields
	# something the player wanted from that hex"); the slice ends when the ground
	# produces.
	_objectives.append({"id": OBJECTIVE_FARM, "title": "Claim it: build a farm on %s" % VerticalSliceConfig.TARGET_NAME, "detail": "A Smallholding Farm (100 Wood) anywhere on the cleared hex", "progress": 0.0, "state": &"active", "required": true})
	dispatch.emit("%s is cleared" % VerticalSliceConfig.TARGET_NAME.capitalize(),
		"Fewer than %d dead remain, so the hex is Cleared: every building the colony can raise may now go there. Claim it — put a Smallholding Farm on it (Agriculture, 100 Wood). It stays cleared only while the dead are kept off it." % _target_threshold,
		HexCoord.axial_to_world(VerticalSliceConfig.TARGET_HEX), ZOOM_HEX_SCALE, false)


func _refresh_horde_objective() -> void:
	var objective := _objective(OBJECTIVE_HORDE)
	if objective.is_empty() or objective["state"] != &"active":
		return
	if _horde == null or not _hordes.get_all_hordes().has(_horde):
		return  # _on_horde_removed() decides.
	objective["progress"] = 1.0 - clampf(float(_horde.size) / float(VerticalSliceConfig.HORDE_SIZE), 0.0, 1.0)
	var distance := HexCoord.distance(VerticalSliceConfig.START_HEX, _horde.hex_coord)
	var doing := "drawn to %s" % _horde.attraction_source.definition.display_name if _horde.attraction_source else "wandering"
	if _horde.state == GameEnums.HordeState.ATTACKING:
		doing = "at your wall"
	objective["detail"] = "%d strong, %d hex%s %s, %s" % [_horde.size, distance, "" if distance == 1 else "es", _bearing_word(VerticalSliceConfig.START_HEX, _horde.hex_coord), doing]


func _refresh_farm_objective() -> void:
	var objective := _objective(OBJECTIVE_FARM)
	if objective.is_empty() or objective["state"] != &"active":
		return
	for instance in _buildings.get_buildings_at(VerticalSliceConfig.TARGET_HEX):
		if instance.definition.soil_fertility_scales_output:
			objective["progress"] = 0.5 if instance.is_under_construction else 1.0
			if not instance.is_under_construction:
				objective["state"] = &"done"
				objective["detail"] = "%s working the plain" % instance.definition.display_name
			else:
				objective["detail"] = "%s under construction" % instance.definition.display_name
			return


func _on_horde_attracted(horde: Horde, source: BuildingInstance, kind: StringName) -> void:
	if horde != _horde:
		return
	_horde_ever_attracted = true
	var what := "the light of your %s" % source.definition.display_name if kind == NoiseManager.KIND_LIGHT else "the noise of your %s" % source.definition.display_name
	var eta := _hordes.get_eta_seconds(horde)
	dispatch.emit("It has found you",
		"The horde caught %s and turned toward it — %d hex%s out, about %s at this speed. Switch that off and it loses you; keep it lit and meet it at the wall with archers within %d m of the piece it hits." % [
			what, HexCoord.distance(horde.hex_coord, source.hex_coord), "" if HexCoord.distance(horde.hex_coord, source.hex_coord) == 1 else "es", _format_real(eta), int(WallDefenseController.RANGED_REACH_METRES)],
		_horde_world(horde), ZOOM_HEX_SCALE, true)


func _on_horde_lost_attraction(horde: Horde, previous_source: BuildingInstance) -> void:
	if horde != _horde or _hordes.get_all_hordes().has(horde) == false:
		return
	var why := "it moved out of reach of"
	if previous_source.is_powered_down:
		why = "you switched off"
	elif previous_source.is_ruined:
		why = "the horde destroyed"
	elif TimeCycleManager.is_day():
		why = "dawn put out"
	dispatch.emit("It has lost you",
		"The horde is wandering again: %s the %s that drew it. Nothing of yours reaches it now." % [why, previous_source.definition.display_name],
		_horde_world(horde), ZOOM_HEX_SCALE, false)


func _on_horde_siege_started(horde: Horde, segment: WallSegment) -> void:
	if horde != _horde:
		return
	var undefended_seconds := segment.current_hp / maxf(0.001, float(HordeManager.wall_contact_frontage(horde.size)) * HordeManager.WALL_DAMAGE_PER_CONTACT_ZOMBIE * HordeManager.WALL_SIEGE_DAMAGE_MULTIPLIER * HordeManager.get_night_aggression_multiplier() / HordeManager.LOGIC_TICK_SECONDS)
	dispatch.emit("At the wall",
		"%d are clawing at a %s. Undefended it falls in about %s. Units within %d m (bows) or %d m (hand weapons) of it on your side strike from cover every volley and take nothing back." % [
			horde.size, "gate" if segment.is_gate else "wall piece", _format_real(undefended_seconds), int(WallDefenseController.RANGED_REACH_METRES), int(WallDefenseController.MELEE_REACH_METRES)],
		(segment.point_a + segment.point_b) * 0.5, ZOOM_WALL_SCALE, true)


func _on_horde_removed(horde: Horde) -> void:
	if horde != _horde:
		return
	var objective := _objective(OBJECTIVE_HORDE)
	if horde.size <= 0:
		_horde = null
		if not objective.is_empty() and objective["state"] == &"active":
			objective["state"] = &"done"
			objective["progress"] = 1.0
			objective["detail"] = "Destroyed"
			dispatch.emit("The horde is destroyed", "All %d are down." % VerticalSliceConfig.HORDE_SIZE, HexCoord.axial_to_world(VerticalSliceConfig.START_HEX), ZOOM_HEX_SCALE, false)
		return
	# Merged into another horde on its hex: follow the survivor.
	var survivors := _hordes.get_hordes_at(horde.hex_coord)
	_horde = survivors[0] if not survivors.is_empty() else null


func _on_phase_changed(phase: GameEnums.DayPhase) -> void:
	if phase == GameEnums.DayPhase.NIGHT:
		var lamps := _lit_lamps_at_start()
		var reach := NoiseManager.light_reach_hexes(lamps, HordeManager.ATTRACTION_THRESHOLD)
		dispatch.emit("Nightfall",
			"%d lamp%s lit: the town is seen from %d hex%s, and the dead move four times faster in the dark. Each Watchtower switched off shortens that by a hex, and costs its night vision." % [lamps, "" if lamps == 1 else "s", reach, "" if reach == 1 else "es"],
			HexCoord.axial_to_world(VerticalSliceConfig.START_HEX), ZOOM_HEX_SCALE, false)
		return
	if not _horde_released:
		return
	_dawns_since_release += 1
	var objective := _objective(OBJECTIVE_HORDE)
	if objective.is_empty() or objective["state"] != &"active" or _horde == null:
		return
	var distance := HexCoord.distance(VerticalSliceConfig.START_HEX, _horde.hex_coord)
	if _horde.attraction_source == null and _horde.state != GameEnums.HordeState.ATTACKING and distance >= VerticalSliceConfig.DRIVEN_OFF_HEXES:
		objective["state"] = &"done"
		objective["progress"] = 1.0
		objective["detail"] = "Driven off — %d hexes out at dawn with nothing to follow" % distance
		dispatch.emit("Dawn — it never found you", "The horde is %d hexes out and wandering. It is still out there, and the next dark night your lamps will show you to it again." % distance, _horde_world(_horde), ZOOM_HEX_SCALE, false)
		objectives_changed.emit()


func _on_band_changed(coord: Vector2i, band: GameEnums.InfestationBand) -> void:
	if coord == VerticalSliceConfig.TARGET_HEX and band == GameEnums.InfestationBand.CLEARED:
		_complete_clear()
		objectives_changed.emit()


func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	if instance.definition.building_type == GameEnums.BuildingType.TOWN_HALL and instance.hex_coord == VerticalSliceConfig.START_HEX:
		_finish(&"defeat")


func _on_wall_breached(segment: WallSegment) -> void:
	if not segment.connects(VerticalSliceConfig.START_HEX):
		return
	dispatch.emit("The wall is breached",
		"A %s has fallen. Whatever is clawing at it walks into the town next, and units it meets in the open fight the whole horde, not a wall's width of it. Pull back, or get archers onto the next piece." % ("gate" if segment.is_gate else "wall piece"),
		(segment.point_a + segment.point_b) * 0.5, ZOOM_WALL_SCALE, true)


func _finish(outcome: StringName) -> void:
	if _finished:
		return
	_finished = true
	for objective in _objectives:
		if objective["state"] == &"active" and objective["required"]:
			objective["state"] = &"failed"
	objectives_changed.emit()
	slice_finished.emit(outcome)


func _all_required_done() -> bool:
	if not _horde_released:
		return false
	for objective in _objectives:
		if objective["required"] and objective["state"] != &"done":
			return false
	return true


func _objective(id: StringName) -> Dictionary:
	for objective in _objectives:
		if objective["id"] == id:
			return objective
	return {}


func _lit_lamps_at_start() -> int:
	var count := 0
	for instance in _buildings.get_buildings_at(VerticalSliceConfig.START_HEX):
		if instance.definition.lit_at_night and instance.is_running():
			count += 1
	return count


## Game-seconds as real time at TickManager's default speed, which is how long the
## player actually has.
static func _horde_world(horde: Horde) -> Vector2:
	return HexCoord.axial_to_world(horde.hex_coord) + horde.local_position


static func _format_real(game_seconds: float) -> String:
	var real := int(round(game_seconds / TickManager.SPEED_MULTIPLIERS[1]))
	if real < 60:
		return "%d s" % real
	return "%d:%02d" % [real / 60, real % 60]


static func _bearing_word(from_coord: Vector2i, to_coord: Vector2i) -> String:
	var delta := HexCoord.axial_to_world(to_coord) - HexCoord.axial_to_world(from_coord)
	if delta.length() < 0.001:
		return "here"
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var index := int(round(fposmod(delta.angle(), TAU) / (TAU / 8.0))) % 8
	return names[index]
