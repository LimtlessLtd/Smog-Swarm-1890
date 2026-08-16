class_name LogisticsNetwork
extends Node

## Supply-line graph and Zone of Control tracker. Reads building placements
## from BuildingManager and secured/contested district state from
## HexGridMap/HexCell; owns neither, only derives ZoC coverage and supply
## connectivity from them.
##
## - Military ZoC: projected by Forward Ammo Dumps, Garrisons and Church
##   Steeple Watchtowers (their MILITARY zoc_role). Covers
##   MILITARY_AURA_COVERAGE (66%) of every hex within MILITARY_AURA_RADIUS —
##   extends across hex borders, not limited to the projecting hex's own
##   coord. Same flat-radius-aura shape (no distance falloff)
##   FogOfWarManager.vision_radius/NoiseManager.NOISE_RADIUS already use —
##   MILITARY_AURA_RADIUS is a placeholder balancing number. Deactivates if
##   every supply line connected to the PROJECTING hex specifically is
##   severed — a projector with no supply lines at all is treated as
##   self-sufficient, since disruption only makes sense once it's actually
##   wired into the network. This severance/territory gate is checked
##   against the PROJECTING hex only, not every hex in its radius — losing
##   supply at the source silences the whole aura, but which hexes it would
##   have covered isn't itself a severance condition.
## - Civilian ZoC: projected by Town Halls, Churches (the Watchtower's
##   civilian half) and Telegraph Relay Offices (their CIVILIAN zoc_role).
##   Covers the entire projecting hex, but only while that hex still has at
##   least one secured (non-contested) district. Not supply-line sensitive
##   — severance only applies to Military ZoC.
##
## Military ZoC also checks TerritoryController.is_lost() — a hex flipped
## to contested (a building there was overwhelmed and ruined while a horde
## occupied it) loses whatever Civilian/Military ZoC coverage it was
## projecting, not just the civilian half. Deliberately NOT the same
## _has_secured_ground() check Civilian ZoC uses, even though both are "is
## this hex safe" in spirit: that check requires the hex to ALREADY have a
## safe district (only true for settlement hexes), which would break the
## Forward Ammo Dump's own "no biome/settlement restriction" design — it
## projects Military ZoC into not-yet-secured frontier hexes, and ordinary
## unclaimed wilderness never had a safe district to lose in the first
## place, so it must never read as "lost territory". is_lost() only returns
## true for a hex TerritoryController itself flipped, which is exactly the
## narrower "this SPECIFIC hex fell" signal Military ZoC needs.
## territory_controller_path is optional — unset means no hex is ever
## territorially lost.
##
## Sub-Hex Mechanical Layer Phase 5a (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — Military ZoC (both the building aura and the mobile
## MOBILE_SUPPLY_DUMP aura) sizes its reach by the projecting source's real
## hex_coord + local_position via HexCoord.sub_hex_disk() (_apply_military_aura()
## below), the same shared utility FogOfWarManager's vision coverage uses
## (Phase 4) — a source near its hex's edge projects an asymmetric aura
## shifted toward wherever it actually sits, never further than a
## hex-centered source at the same radius would (see HexCoord.
## fractional_hex_distance()'s own doc comment for the proof). Civilian ZoC
## is untouched — it covers only the whole projecting hex itself, no radius
## disk involved, nothing for sub-hex position to refine.

signal network_recomputed

const MILITARY_AURA_COVERAGE: float = 0.66
const MILITARY_AURA_RADIUS: int = 1  ## How far (in hexes) Military ZoC projects beyond its own hex.

## The Searchlight Tender (GameEnums.UnitAbility.MOBILE_SUPPLY_DUMP) "acts
## as a mobile ammo supply dump, just with much reduced military zone of
## control" — 0 (its own hex only) vs. a stationary Forward Ammo Dump's
## MILITARY_AURA_RADIUS of 1. Doubles as the unit's own moving vision
## source too (FogOfWarManager treats ZoC coverage as vision), which is
## what actually illuminates infected sectors around it. Still
## hex_disk(), not a direct single-hex write, so a future balancing pass
## can raise this without restructuring the loop below.
const MOBILE_SUPPLY_AURA_RADIUS: int = 0

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var territory_controller_path: NodePath  ## Optional — unset skips recompute-on-territory-change; _has_secured_ground() still reads live HexCell.districts state either way.
@export var unit_manager_path: NodePath          ## Optional — the MOBILE_SUPPLY_DUMP ability (Searchlight Tender); unset means no unit ever projects ZoC.
@export var unit_order_controller_path: NodePath ## Optional — recompute-on-move for the mobile aura above; without this, a MOBILE_SUPPLY_DUMP unit's aura only updates on train/remove, not as it walks.

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _territory_controller: TerritoryController
var _unit_manager: UnitManager
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
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_trained.connect(_on_units_changed)
		_unit_manager.unit_removed.connect(_on_units_changed)
	if unit_order_controller_path != NodePath():
		var unit_order_controller: UnitOrderController = get_node(unit_order_controller_path)
		unit_order_controller.unit_moved.connect(_on_unit_moved)
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

## The supply line segment (of either endpoint order) connecting `hex_a`
## and `hex_b`, or null if none exists. Exposed for ReclamationManager to
## check severed state before offering a costed repair —
## SupplyLineSegment.connects()/other_end() already give a segment its own
## adjacency helpers, this is just the network-wide lookup by pair.
func get_segment_between(hex_a: Vector2i, hex_b: Vector2i) -> SupplyLineSegment:
	for segment in _segments:
		if (segment.hex_a == hex_a and segment.hex_b == hex_b) or (segment.hex_a == hex_b and segment.hex_b == hex_a):
			return segment
	return null

## Segments + severed state only; ZoC coverage (_zoc_by_hex) is
## deliberately not part of this, it recomputes fresh from buildings +
## these segments every time (see recompute()).
func get_save_segments() -> Array[SupplyLineSegment]:
	return _segments.duplicate()

func load_save_segments(segments: Array[SupplyLineSegment]) -> void:
	_segments = segments.duplicate()
	recompute()

## Every hex currently carrying any Zone of Control coverage (military or
## civilian). Lets FogOfWarManager treat ZoC coverage as a vision source
## without reaching into this class's internals.
func get_covered_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_zoc_by_hex.keys())
	return result

## Every hex currently carrying Civilian ZoC coverage specifically —
## narrower than get_covered_hexes() (which includes Military-only hexes
## too). Lets DiscontentManager flood-fill "Civilian Region" boundaries
## without reaching into this class's internals; matches the project's own
## definition of a Civilian Region as a maximal connected cluster of
## has_civilian_coverage hexes.
func get_civilian_covered_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _zoc_by_hex:
		if _zoc_by_hex[coord].has_civilian_coverage:
			result.append(coord)
	return result

## True if `to_coord` is reachable from `from_coord` over unsevered supply
## lines only. A general connectivity primitive for later phases; today's
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

## Recomputes every hex's ZoC coverage from scratch. Cheap enough to call
## on every building/supply-line change at this scale (dozens of
## buildings, not thousands) — revisit with incremental updates if that
## stops being true.
func recompute() -> void:
	_zoc_by_hex.clear()
	if _building_manager:
		for instance in _building_manager.get_buildings_with_zoc_role(GameEnums.ZoneOfControlType.CIVILIAN):
			# A ruined building is rubble, not a functioning civic seat —
			# projects nothing, independent of district/territory state
			# (which a recapture can flip back to safe without the ruin
			# itself ever being repaired).
			if instance.is_ruined or not _has_secured_ground(instance.hex_coord):
				continue
			_state_for(instance.hex_coord).has_civilian_coverage = true

		for instance in _building_manager.get_buildings_with_zoc_role(GameEnums.ZoneOfControlType.MILITARY):
			if instance.is_ruined or not _is_supply_intact(instance.hex_coord) or _is_territorially_lost(instance.hex_coord):
				continue
			_apply_military_aura(instance.hex_coord, instance.local_position, MILITARY_AURA_RADIUS)

	# The Searchlight Tender's mobile supply dump — same MILITARY_AURA_COVERAGE
	# fraction a building projects, just from wherever the unit currently
	# stands and at MOBILE_SUPPLY_AURA_RADIUS instead of MILITARY_AURA_RADIUS.
	# A sibling of the `if _building_manager:` block above, not nested
	# inside it — must keep working even with no BuildingManager wired at all.
	# Not gated on supply-line intactness or territory loss the way a
	# building's Military ZoC is — a mobile unit has no supply line of its
	# own to sever and isn't "lost territory" in TerritoryController's
	# sense, it just walks away; the only real gate is "does this unit
	# still exist" (is_destroyed()).
	if _unit_manager:
		for instance: UnitInstance in _unit_manager.get_all_units():
			if instance.definition.ability != GameEnums.UnitAbility.MOBILE_SUPPLY_DUMP or instance.is_destroyed():
				continue
			_apply_military_aura(instance.hex_coord, instance.local_position, MOBILE_SUPPLY_AURA_RADIUS)
	network_recomputed.emit()

## Applies MILITARY_AURA_COVERAGE to every hex within `radius` of a source
## sitting at `source_local_position` inside `source_hex`, via
## HexCoord.sub_hex_disk() — shared by the building and mobile-unit auras
## above (Sub-Hex Mechanical Layer Phase 5a, see this class's own doc
## comment). Not gated on _hex_grid_map.has_cell() the way FogOfWarManager's
## own vision-disk loop is — a coord with no real HexCell behind it never
## gets queried by anything real, so skipping the check costs nothing and
## keeps this loop simple.
func _apply_military_aura(source_hex: Vector2i, source_local_position: Vector2, radius: int) -> void:
	for coord in HexCoord.sub_hex_disk(source_hex, source_local_position, radius):
		var state := _state_for(coord)
		state.military_coverage = maxf(state.military_coverage, MILITARY_AURA_COVERAGE)

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

func _on_units_changed(_instance: UnitInstance) -> void:
	recompute()

## Recomputes on every hex boundary a unit actually crosses (same signal
## CombatCoordinator wires) so a MOBILE_SUPPLY_DUMP unit's aura visibly
## follows it as it walks, not just on training/loss. Fires for every
## unit's every hex crossing, not just the rare MOBILE_SUPPLY_DUMP one —
## recompute() is "cheap enough... revisit with incremental updates if
## that stops being true" per this class's own doc comment, now exercised
## by unit movement too.
func _on_unit_moved(_instance: UnitInstance, _from_coord: Vector2i, _to_coord: Vector2i) -> void:
	recompute()
