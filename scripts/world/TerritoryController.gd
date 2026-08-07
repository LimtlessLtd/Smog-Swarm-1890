class_name TerritoryController
extends Node

## Design doc Phase 5.8: the missing mechanism that lets a District's
## is_contested flag flip during actual play — DistrictPartitioner (Phase 1)
## only ever sets it once, at map generation, and nothing since has ever
## changed it.
##
## **Loss trigger, decided here:** a hex's safe (non-`UNCLEARED_WILDERNESS`)
## districts flip to contested the moment a `BuildingInstance` ON THAT HEX
## is ruined (Phase 5.12's `BuildingManager.building_ruined`) while at least
## one `Horde` currently occupies the hex. "A zombie assault overwhelms
## whatever's defending it" (design doc) made concrete: an actual building
## being destroyed IS the overwhelm event, not merely an undefended horde
## passing through — ties Loss directly to Building Ruins rather than a
## vaguer "no unit present" instant-flip, which would make territory
## flicker contested on every momentary undefended visit that never
## actually cost the player anything.
##
## **Recapture trigger, decided here:** a hex this controller flipped
## reverts to safe once no `Horde` occupies it any longer — "once the
## player clears it of zombies" (design doc) is the literal, sole
## condition; no rebuild/repair requirement. Checked off `HordeManager.
## horde_moved` (the hex a horde just LEFT may now be clear) and
## `horde_removed` (a horde destroyed while sitting on a previously-lost hex).
##
## Losing/regaining a safe district changes what `LogisticsNetwork.
## _has_secured_ground()` sees (`HexCell.get_safe_districts()`) —
## `district_state_changed` is a plain signal `LogisticsNetwork` itself
## subscribes to and recomputes off, the same "recompute on the signal"
## precedent every other manager here already follows, rather than this
## class reaching into `LogisticsNetwork`'s recompute() directly.
##
## Only ever flips districts it itself flipped (`_lost_hexes` bookkeeping)
## — a hex that started fully wild with no safe district to begin with is
## never touched, and recapture never has to guess which districts "should"
## be safe again versus were already correctly safe/contested for some
## other reason.

signal district_state_changed(coord: Vector2i, is_contested: bool)
signal territory_lost(coord: Vector2i)
signal territory_recaptured(coord: Vector2i)

@export var hex_grid_map_path: NodePath
@export var horde_manager_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _horde_manager: HordeManager

## Hexes this controller itself flipped to contested. See this class's own
## doc comment on why recapture only ever reverts state it caused.
var _lost_hexes: Dictionary = {}  # Vector2i -> true

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
		_horde_manager.horde_moved.connect(_on_horde_moved)
		_horde_manager.horde_removed.connect(_on_horde_removed)
	if building_manager_path != NodePath():
		var building_manager: BuildingManager = get_node(building_manager_path)
		building_manager.building_ruined.connect(_on_building_ruined)

func is_lost(coord: Vector2i) -> bool:
	return _lost_hexes.has(coord)

func get_lost_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_lost_hexes.keys())
	return result

func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	if not _horde_manager or _horde_manager.get_hordes_at(instance.hex_coord).is_empty():
		return  # A ruin with no horde present to have caused it isn't a territorial loss — see this class's own doc comment.
	_flip_to_contested(instance.hex_coord)

func _on_horde_moved(_horde: Horde, from_coord: Vector2i, _to_coord: Vector2i) -> void:
	_check_recapture(from_coord)

func _on_horde_removed(horde: Horde) -> void:
	_check_recapture(horde.hex_coord)

func _check_recapture(coord: Vector2i) -> void:
	if not _lost_hexes.has(coord) or not _horde_manager:
		return
	if not _horde_manager.get_hordes_at(coord).is_empty():
		return  # Still occupied by at least one other horde — not clear yet.
	_flip_to_safe(coord)

func _flip_to_contested(coord: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	var changed := false
	for district in cell.districts:
		if district.type != GameEnums.DistrictType.UNCLEARED_WILDERNESS and not district.is_contested:
			district.is_contested = true
			changed = true
	if not changed:
		return  # Already fully contested (or never had a safe district) — nothing to flip.
	_lost_hexes[coord] = true
	district_state_changed.emit(coord, true)
	territory_lost.emit(coord)

func _flip_to_safe(coord: Vector2i) -> void:
	_lost_hexes.erase(coord)
	if not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	for district in cell.districts:
		if district.type != GameEnums.DistrictType.UNCLEARED_WILDERNESS:
			district.is_contested = false
	district_state_changed.emit(coord, false)
	territory_recaptured.emit(coord)

## Exposed for SaveLoadManager (Phase 2.8) — see ReclamationManager's own
## doc comment for the precedent: Phase 2.8.1's "terrain regenerates
## byte-identically from a fixed seed, no saving needed" baseline doesn't
## hold once this class can mutate a live HexCell's district state, so
## which hexes are territorially lost is the one piece of district state
## that actually needs persisting.
func get_save_state() -> Dictionary:
	var result: Array[Vector2i] = []
	result.assign(_lost_hexes.keys())
	return {"lost_hexes": result}

## Restores lost-territory state directly (bypassing the horde-presence
## check _flip_to_contested() itself doesn't gate on either — a save is
## authoritative for what was true at save time, not something to
## re-validate against whatever's on the map right now). Deliberately does
## NOT emit district_state_changed — same restraint ReclamationManager.
## load_save_state() already shows; LogisticsNetwork's own recompute()
## naturally reads the correctly-restored district state once buildings
## finish restoring afterward (see SaveLoadManager's own restoration-order
## doc comment for why this runs before that).
func load_save_state(lost_hexes: Array[Vector2i]) -> void:
	_lost_hexes.clear()
	if not _hex_grid_map:
		return
	for coord in lost_hexes:
		var cell := _hex_grid_map.get_cell(coord)
		if not cell:
			continue
		for district in cell.districts:
			if district.type != GameEnums.DistrictType.UNCLEARED_WILDERNESS:
				district.is_contested = true
		_lost_hexes[coord] = true
