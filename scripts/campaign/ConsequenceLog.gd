class_name ConsequenceLog
extends Node

## A timeline of what the player did and what the world did about it, recorded
## from the simulation's own signals: a lamp switched off, a horde that caught the
## light and turned, the wall piece it clawed at, how many fell to defenders behind
## it. PLAYER_EXPERIENCE.md asks that the player "immediately understand why what I
## did mattered"; VerticalSliceDebrief reads this to say so, and nothing here
## decides anything.
##
## Each entry: {"seconds": game-seconds since day 1 began, "kind": StringName,
## "text": String, "coord": Vector2i, "data": Dictionary}. Kinds are the KIND_*
## constants. Volleys are folded into their siege rather than logged one per ten
## game-seconds.

signal entry_added(entry: Dictionary)

const KIND_POWER_DOWN := &"power_down"
const KIND_POWER_UP := &"power_up"
const KIND_ATTRACTED := &"attracted"
const KIND_LOST := &"lost"
const KIND_SIEGE := &"siege"
const KIND_BREACH := &"breach"
const KIND_HORDE_DESTROYED := &"horde_destroyed"
const KIND_UNIT_LOST := &"unit_lost"
const KIND_BUILDING_RUINED := &"building_ruined"
const KIND_CLEARED := &"cleared"
const KIND_NIGHTFALL := &"nightfall"
const KIND_DAWN := &"dawn"

@export var horde_manager_path: NodePath
@export var building_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var wall_defense_controller_path: NodePath
@export var combat_coordinator_path: NodePath
@export var infestation_manager_path: NodePath

var _hordes: HordeManager
var _buildings: BuildingManager
var _walls: WallManager
var _wall_defense: WallDefenseController
var _combat: CombatCoordinator
var _infestation: InfestationManager

var _entries: Array[Dictionary] = []
var _kills_from_cover: int = 0
var _kills_in_contact: int = 0
var _kills_by_hex: Dictionary = {}          # Vector2i -> int, contact kills (residents and hordes) per hex
var _siege_kills: Dictionary = {}           # Horde -> int, kills from cover during its current siege
var _siege_peak_defenders: Dictionary = {}  # Horde -> int
var _units_lost: int = 0
var _cleared_hexes: Dictionary = {}          # Vector2i -> true once logged, so a hex is reported cleared once
var _seen_uncleared: Dictionary = {}         # Vector2i -> true once a fight there happened while it was not cleared
var _wall_damage_taken: float = 0.0


func _ready() -> void:
	if horde_manager_path:
		_hordes = get_node_or_null(horde_manager_path) as HordeManager
	if building_manager_path:
		_buildings = get_node_or_null(building_manager_path) as BuildingManager
	if wall_manager_path:
		_walls = get_node_or_null(wall_manager_path) as WallManager
	if wall_defense_controller_path:
		_wall_defense = get_node_or_null(wall_defense_controller_path) as WallDefenseController
	if combat_coordinator_path:
		_combat = get_node_or_null(combat_coordinator_path) as CombatCoordinator
	if infestation_manager_path:
		_infestation = get_node_or_null(infestation_manager_path) as InfestationManager

	if _hordes:
		_hordes.horde_attracted.connect(_on_horde_attracted)
		_hordes.horde_lost_attraction.connect(_on_horde_lost_attraction)
		_hordes.horde_siege_started.connect(_on_horde_siege_started)
		_hordes.horde_removed.connect(_on_horde_removed)
	if _buildings:
		_buildings.building_powered_down.connect(_on_powered_down)
		_buildings.building_powered_up.connect(_on_powered_up)
		_buildings.building_ruined.connect(_on_building_ruined)
	if _walls:
		_walls.wall_segment_breached.connect(_on_wall_breached)
		_walls.wall_segment_damaged.connect(func(_segment: WallSegment, amount: float) -> void: _wall_damage_taken += amount)
	if _wall_defense:
		_wall_defense.volley_resolved.connect(_on_volley_resolved)
	if _combat:
		_combat.engagement_resolved.connect(_on_engagement_resolved)
	if _infestation:
		_infestation.band_changed.connect(_on_band_changed)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

## Counts the debrief reads: kills_from_cover, kills_in_contact, units_lost,
## wall_damage_taken.
func get_totals() -> Dictionary:
	return {
		"kills_from_cover": _kills_from_cover,
		"kills_in_contact": _kills_in_contact,
		"units_lost": _units_lost,
		"wall_damage_taken": _wall_damage_taken,
	}

func get_contact_kills_at(coord: Vector2i) -> int:
	return int(_kills_by_hex.get(coord, 0))

static func now_seconds() -> float:
	return float(TickManager.current_day - 1) * TickManager.DAY_LENGTH_SECONDS + TickManager.elapsed_in_day


func _add(kind: StringName, text: String, coord: Vector2i, data: Dictionary = {}) -> void:
	var entry := {"seconds": now_seconds(), "kind": kind, "text": text, "coord": coord, "data": data}
	_entries.append(entry)
	entry_added.emit(entry)


func _on_powered_down(instance: BuildingInstance) -> void:
	_add(KIND_POWER_DOWN, "You switched off the %s." % instance.definition.display_name, instance.hex_coord,
		{"building": instance.definition.display_name, "lit": instance.definition.lit_at_night, "noise_db": instance.definition.noise_source_db})

func _on_powered_up(instance: BuildingInstance) -> void:
	_add(KIND_POWER_UP, "The %s is running again." % instance.definition.display_name, instance.hex_coord,
		{"building": instance.definition.display_name})

func _on_horde_attracted(horde: Horde, source: BuildingInstance, kind: StringName) -> void:
	var sense := "saw the light of" if kind == NoiseManager.KIND_LIGHT else "heard"
	_add(KIND_ATTRACTED, "A horde of %d %s your %s from %d hex%s out and turned toward it." % [horde.size, sense, source.definition.display_name, HexCoord.distance(horde.hex_coord, source.hex_coord), "" if HexCoord.distance(horde.hex_coord, source.hex_coord) == 1 else "es"],
		horde.hex_coord, {"horde_size": horde.size, "source": source.definition.display_name, "kind": kind, "distance": HexCoord.distance(horde.hex_coord, source.hex_coord), "eta_seconds": _hordes.get_eta_seconds(horde) if _hordes else 0.0, "night": TimeCycleManager.is_night()})

func _on_horde_lost_attraction(horde: Horde, previous_source: BuildingInstance) -> void:
	var cause := &"out_of_reach"
	var text := "A horde of %d moved out of reach of your %s and wandered." % [horde.size, previous_source.definition.display_name]
	if previous_source.is_powered_down:
		cause = &"switched_off"
		text = "A horde of %d lost your %s when you switched it off, and wandered." % [horde.size, previous_source.definition.display_name]
	elif previous_source.is_ruined:
		cause = &"ruined"
		text = "A horde of %d lost your %s when it fell." % [horde.size, previous_source.definition.display_name]
	elif TimeCycleManager.is_day() and previous_source.definition.lit_at_night:
		cause = &"dawn"
		text = "Dawn put your %s out; a horde of %d lost it and wandered." % [previous_source.definition.display_name, horde.size]
	_add(KIND_LOST, text, horde.hex_coord, {"horde_size": horde.size, "source": previous_source.definition.display_name, "cause": cause, "distance": HexCoord.distance(horde.hex_coord, previous_source.hex_coord)})

func _on_horde_siege_started(horde: Horde, segment: WallSegment) -> void:
	_siege_kills[horde] = 0
	_siege_peak_defenders[horde] = 0
	_add(KIND_SIEGE, "A horde of %d reached your wall and began clawing at a %s." % [horde.size, "gate" if segment.is_gate else "wall piece"],
		horde.hex_coord, {"horde_size": horde.size, "segment_hp": segment.current_hp, "gate": segment.is_gate, "night": TimeCycleManager.is_night()})

func _on_volley_resolved(horde: Horde, _segment: WallSegment, defenders: int) -> void:
	_siege_peak_defenders[horde] = maxi(int(_siege_peak_defenders.get(horde, 0)), defenders)

func _on_engagement_resolved(instance: UnitInstance, horde: Horde, result: Dictionary) -> void:
	var killed := int(result.get("zombies_killed", 0))
	if result.get("from_cover", false):
		_kills_from_cover += killed
		_siege_kills[horde] = int(_siege_kills.get(horde, 0)) + killed
	else:
		_kills_in_contact += killed
		_kills_by_hex[horde.hex_coord] = int(_kills_by_hex.get(horde.hex_coord, 0)) + killed
		_check_cleared(horde.hex_coord)
	if instance.is_destroyed():
		_units_lost += 1
		_add(KIND_UNIT_LOST, "A %s squad was wiped out fighting in the open." % instance.definition.display_name, instance.hex_coord,
			{"unit": instance.definition.display_name, "horde_size": horde.size, "from_cover": result.get("from_cover", false)})

## Only hordes that besieged a wall are logged as destroyed. A hex's residents come
## out to fight as a fresh horde every wave (ResidentDefenseController) and each
## one that dies is removed too — logging those buried a slice's debrief under
## dozens of identical lines.
func _on_horde_removed(horde: Horde) -> void:
	if horde.size > 0 or not _siege_kills.has(horde):
		_siege_kills.erase(horde)
		_siege_peak_defenders.erase(horde)
		return
	var cover_kills := int(_siege_kills.get(horde, 0))
	_add(KIND_HORDE_DESTROYED, "A horde was destroyed%s." % (" — %d of it by defenders behind the wall" % cover_kills if cover_kills > 0 else ""),
		horde.hex_coord, {"kills_from_cover": cover_kills, "peak_defenders": int(_siege_peak_defenders.get(horde, 0))})
	_siege_kills.erase(horde)
	_siege_peak_defenders.erase(horde)

func _on_wall_breached(segment: WallSegment) -> void:
	_add(KIND_BREACH, "A %s was breached." % ("gate" if segment.is_gate else "wall piece"), segment.hex_a, {"gate": segment.is_gate})

func _on_building_ruined(instance: BuildingInstance, lost_population: int) -> void:
	_add(KIND_BUILDING_RUINED, "Your %s was ruined%s." % [instance.definition.display_name, " and %d living there rose again" % lost_population if lost_population > 0 else ""],
		instance.hex_coord, {"building": instance.definition.display_name, "lost_population": lost_population})

func _on_band_changed(coord: Vector2i, band: GameEnums.InfestationBand) -> void:
	if band == GameEnums.InfestationBand.CLEARED:
		_log_cleared(coord)


## Clearing by killing residents never emits InfestationManager.band_changed:
## residents leave through condense_defenders(), which writes without the band
## comparison, and die as a horde. So a kill in the field is also when to look.
##
## Only a hex first seen NOT cleared during a fight counts: a horde that breaks into
## the town and loses a couple of zombies there would otherwise read as the town
## being "cleared".
func _check_cleared(coord: Vector2i) -> void:
	if not _infestation or _cleared_hexes.has(coord) or _infestation.capacity_at(coord) <= 0:
		return
	if not _infestation.is_cleared(coord):
		_seen_uncleared[coord] = true
	elif _seen_uncleared.has(coord):
		_log_cleared(coord)


func _log_cleared(coord: Vector2i) -> void:
	if _cleared_hexes.has(coord):
		return
	_cleared_hexes[coord] = true
	_add(KIND_CLEARED, "The ground %s was cleared after %d kills there." % [LocationNames.describe(coord, _buildings), get_contact_kills_at(coord)], coord, {"kills": get_contact_kills_at(coord)})

func _on_phase_changed(phase: GameEnums.DayPhase) -> void:
	if phase == GameEnums.DayPhase.NIGHT:
		_add(KIND_NIGHTFALL, "Night fell.", Vector2i.ZERO)
	else:
		_add(KIND_DAWN, "Dawn.", Vector2i.ZERO)
