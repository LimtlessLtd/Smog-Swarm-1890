class_name LogisticsNetwork
extends Node

## Supply-line graph and Zone of Control tracker (design doc Phase 2.3).
## Reads building placements from BuildingManager and secured/contested
## district state from HexGridMap/HexCell; owns neither, only derives ZoC
## coverage and supply connectivity from them.
##
## - Military ZoC: projected by Forward Ammo Dumps, Garrisons and Church
##   Steeple Watchtowers (their MILITARY zoc_role). Covers
##   MILITARY_AURA_COVERAGE (66%) of the projecting hex only. Deactivates if
##   every supply line connected to the projecting hex is severed (design
##   doc: "If zombies sever a road, rail, or canal segment connected to an
##   Ammo Dump, its Military ZoC supply aura deactivates") — a projector with
##   no supply lines at all is treated as self-sufficient, since disruption
##   only makes sense once it has actually been wired into the network.
## - Civilian ZoC: projected by Town Halls, Churches (the Watchtower's
##   civilian half) and Telegraph Relay Offices (their CIVILIAN zoc_role).
##   Covers the entire projecting hex, but only while that hex still has at
##   least one secured (non-contested) district — design doc: "Can only be
##   placed on secure hex tiles (no zombies)". Not supply-line sensitive;
##   the design doc only calls out severance for Military ZoC.
##
## Phase 5.8: Military ZoC also checks `TerritoryController.is_lost()` now,
## not just supply-line intactness — a hex flipped to contested (a building
## there was overwhelmed and ruined while a horde occupied it) genuinely
## "loses whatever Civilian/Military ZoC coverage it was projecting"
## (design doc Phase 5.8's own Loss bullet), not just the civilian half.
## Deliberately NOT the same `_has_secured_ground()` check Civilian ZoC
## already uses, even though both are "is this hex safe" in spirit: that
## check requires the hex to ALREADY have a safe district (only true for
## settlement hexes per DistrictPartitioner), which would break the Forward
## Ammo Dump's own explicit "no biome/settlement restriction ... projecting
## Military ZoC out into not-yet-secured frontier hexes" design — ordinary
## unclaimed wilderness never had a safe district to lose in the first
## place, so it must never be treated as "lost territory". `is_lost()` only
## ever returns true for a hex TerritoryController itself flipped, which is
## exactly the narrower "this SPECIFIC hex fell" signal Military ZoC needs.
## `territory_controller_path` is optional — unset simply means no hex is
## ever territorially lost yet, same "gracefully skip it" convention every
## other optional dependency here follows.

signal network_recomputed

const MILITARY_AURA_COVERAGE: float = 0.66

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var territory_controller_path: NodePath  ## Optional — Phase 5.8. Unset skips recompute-on-territory-change; _has_secured_ground() still reads live HexCell.districts state either way.

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _territory_controller: TerritoryController
var _segments: Array[SupplyLineSegment] = []
var _zoc_by_hex: Dictionary = {}  # Vector2i -> ZoneOfControlState

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
	if territory_controller_path != NodePath():
		_territory_controller = get_node(territory_controller_path)
		_territory_controller.district_state_changed.connect(_on_territory_changed)
	recompute()

func add_supply_line(line_type: GameEnums.SupplyLineType, hex_a: Vector2i, hex_b: Vector2i) -> SupplyLineSegment:
	var segment := SupplyLineSegment.new(line_type, hex_a, hex_b)
	_segments.append(segment)
	recompute()
	return segment

func sever_segment_between(hex_a: Vector2i, hex_b: Vector2i) -> void:
	_set_severed_between(hex_a, hex_b, true)

func restore_segment_between(hex_a: Vector2i, hex_b: Vector2i) -> void:
	_set_severed_between(hex_a, hex_b, false)

func get_zoc_state(coord: Vector2i) -> ZoneOfControlState:
	return _zoc_by_hex.get(coord, ZoneOfControlState.new(coord))

## The supply line segment (of either endpoint order) connecting `hex_a` and
## `hex_b`, or null if none exists. Exposed for Phase 4.2's
## ReclamationManager to check severed state before offering a costed
## repair — SupplyLineSegment.connects()/other_end() already give a segment
## its own adjacency helpers, this is just the network-wide lookup by pair.
func get_segment_between(hex_a: Vector2i, hex_b: Vector2i) -> SupplyLineSegment:
	for segment in _segments:
		if (segment.hex_a == hex_a and segment.hex_b == hex_b) or (segment.hex_a == hex_b and segment.hex_b == hex_a):
			return segment
	return null

## Exposed for SaveLoadManager (Phase 2.8) — segments + severed state only;
## ZoC coverage (_zoc_by_hex) is deliberately not part of this, it recomputes
## fresh from buildings + these segments every time (see recompute()).
func get_save_segments() -> Array[SupplyLineSegment]:
	return _segments.duplicate()

## Restores supply line segments from a save (Phase 2.8.2) and recomputes
## ZoC/vision coverage against them.
func load_save_segments(segments: Array[SupplyLineSegment]) -> void:
	_segments = segments.duplicate()
	recompute()

## Every hex currently carrying any Zone of Control coverage (military or
## civilian). Lets FogOfWarManager (Phase 2.6) treat ZoC coverage as a vision
## source without reaching into this class's internals.
func get_covered_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_zoc_by_hex.keys())
	return result

## Every hex currently carrying Civilian ZoC coverage specifically — narrower
## than get_covered_hexes() (which includes Military-only hexes too). Lets
## DiscontentManager (Phase 2.11) flood-fill "Civilian Region" boundaries
## without reaching into this class's internals; matches the design doc's
## own definition of a Civilian Region as a maximal connected cluster of
## has_civilian_coverage hexes.
func get_civilian_covered_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _zoc_by_hex:
		if _zoc_by_hex[coord].has_civilian_coverage:
			result.append(coord)
	return result

## True if `to_coord` is reachable from `from_coord` over unsevered supply
## lines only. A general connectivity primitive for later phases (e.g.
## "is this hex linked all the way back to a population hub?"); today's
## severance rule only needs the narrower _is_supply_intact() below.
func is_supply_connected(from_coord: Vector2i, to_coord: Vector2i) -> bool:
	if from_coord == to_coord:
		return true
	var visited := {from_coord: true}
	var frontier: Array[Vector2i] = [from_coord]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for segment in _segments:
			if segment.is_severed or not segment.connects(current):
				continue
			var next := segment.other_end(current)
			if next == to_coord:
				return true
			if not visited.has(next):
				visited[next] = true
				frontier.append(next)
	return false

## Recomputes every hex's ZoC coverage from scratch. Cheap enough to call on
## every building/supply-line change at this scale (dozens of buildings, not
## thousands) — revisit with incremental updates if that stops being true.
func recompute() -> void:
	_zoc_by_hex.clear()
	if _building_manager:
		for instance in _building_manager.get_buildings_with_zoc_role(GameEnums.ZoneOfControlType.CIVILIAN):
			# Phase 5.12: a ruined building is rubble, not a functioning civic
			# seat — it projects nothing, independent of district/territory
			# state (which a Recapture, Phase 5.8, can flip back to safe
			# without the ruin itself ever being repaired).
			if instance.is_ruined or not _has_secured_ground(instance.hex_coord):
				continue
			_state_for(instance.hex_coord).has_civilian_coverage = true

		for instance in _building_manager.get_buildings_with_zoc_role(GameEnums.ZoneOfControlType.MILITARY):
			if instance.is_ruined or not _is_supply_intact(instance.hex_coord) or _is_territorially_lost(instance.hex_coord):
				continue
			var state := _state_for(instance.hex_coord)
			state.military_coverage = maxf(state.military_coverage, MILITARY_AURA_COVERAGE)
	network_recomputed.emit()

func _state_for(coord: Vector2i) -> ZoneOfControlState:
	if not _zoc_by_hex.has(coord):
		_zoc_by_hex[coord] = ZoneOfControlState.new(coord)
	return _zoc_by_hex[coord]

func _has_secured_ground(coord: Vector2i) -> bool:
	if not _hex_grid_map:
		return false
	var cell := _hex_grid_map.get_cell(coord)
	return cell != null and not cell.get_safe_districts().is_empty()

func _is_territorially_lost(coord: Vector2i) -> bool:
	return _territory_controller != null and _territory_controller.is_lost(coord)

func _is_supply_intact(coord: Vector2i) -> bool:
	var connected_segments := _segments.filter(func(segment: SupplyLineSegment) -> bool:
		return segment.connects(coord)
	)
	if connected_segments.is_empty():
		return true
	for segment in connected_segments:
		if not segment.is_severed:
			return true
	return false

func _set_severed_between(hex_a: Vector2i, hex_b: Vector2i, severed: bool) -> void:
	for segment in _segments:
		if (segment.hex_a == hex_a and segment.hex_b == hex_b) or (segment.hex_a == hex_b and segment.hex_b == hex_a):
			segment.is_severed = severed
	recompute()

func _on_buildings_changed(_instance: BuildingInstance) -> void:
	recompute()

func _on_territory_changed(_coord: Vector2i, _is_contested: bool) -> void:
	recompute()
