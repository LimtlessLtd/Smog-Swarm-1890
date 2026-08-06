class_name WallManager
extends Node

## Runtime owner of every placed WallSegment (design doc Phase 4.1). Mirrors
## BuildingManager's shape (validate -> spend -> register) and
## LogisticsNetwork's "chain of individually-tracked segments between hex
## pairs" shape — walls are the same idea, just defensive instead of
## logistical, and each segment carries its OWN health pool rather than a
## shared network-wide state (design doc, decided).
##
## Ditches and Oil Pits are deliberately NOT placed through
## BuildingManager.place_building() despite being real BuildingCatalog
## entries (Phase 2.1, added here in Phase 4.1): the design doc frames them
## as stacking WITH a specific wall segment ("per segment"), not occupying
## independent hex+local_position the way every other building does. This
## class reuses BuildingCatalog purely as their cost-data source
## (add_defense_work() below) and tracks which segment has which as a plain
## bool flag on WallSegment, rather than inventing a second building-tree
## system or awkwardly bolting them onto BuildingManager's placement flow.
##
## Combat — a horde damaging a segment, a siege bonus, Ditches/Oil Pits
## actually inflicting counter-damage — is entirely Phase 5's job
## (CombatEngine 5.4, horde AI 5.10). damage_segment() below is the real,
## callable hook that phase will use; nothing calls it yet.

signal wall_segment_placed(segment: WallSegment)
signal wall_segment_upgraded(segment: WallSegment)
signal wall_segment_damaged(segment: WallSegment, amount: float)
signal wall_segment_breached(segment: WallSegment)
signal defense_work_added(segment: WallSegment, work_type: GameEnums.BuildingType)
signal placement_rejected(hex_a: Vector2i, hex_b: Vector2i, reason: String)
signal upgrade_rejected(segment: WallSegment, reason: String)

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
## Optional — gates upgrade_segment() against Phase 2.9's Tech Tree. Unset
## means every wall tier is treated as unlocked (no tech-gate check).
@export var tech_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _segments: Array[WallSegment] = []
var _next_id: int = 1

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)

func get_segments() -> Array[WallSegment]:
	return _segments.duplicate()

func get_segment_between(hex_a: Vector2i, hex_b: Vector2i) -> WallSegment:
	for segment in _segments:
		if (segment.hex_a == hex_a and segment.hex_b == hex_b) or (segment.hex_a == hex_b and segment.hex_b == hex_a):
			return segment
	return null

func get_segments_at(coord: Vector2i) -> Array[WallSegment]:
	var result: Array[WallSegment] = []
	for segment in _segments:
		if segment.connects(coord):
			result.append(segment)
	return result

## Exposed for SaveLoadManager (Phase 2.8) — mirrors BuildingManager.get_next_id().
func get_next_id() -> int:
	return _next_id

## Returns "" if a fresh Wooden segment can legally be placed between
## `hex_a`/`hex_b` right now, or a human-readable rejection reason otherwise
## — mirrors BuildingManager.get_placement_error()'s "queryable without side
## effects" pattern.
func get_placement_error(hex_a: Vector2i, hex_b: Vector2i) -> String:
	if not _hex_grid_map:
		return "No hex grid map wired to WallManager."
	if hex_a == hex_b:
		return "A wall segment needs two different hexes."
	if not HexCoord.neighbors(hex_a).has(hex_b):
		return "%s and %s aren't adjacent." % [hex_a, hex_b]
	var cell_a := _hex_grid_map.get_cell(hex_a)
	var cell_b := _hex_grid_map.get_cell(hex_b)
	if not cell_a or not cell_b:
		return "Wall segment is outside the map."
	if not cell_a.is_passable() or not cell_b.is_passable():
		return "Cannot wall off marsh or peat bog until it is drained."
	if get_segment_between(hex_a, hex_b):
		return "A wall segment already defends this edge."
	if _resource_manager and not _resource_manager.can_afford(WallCatalog.get_build_cost(WallCatalog.WOODEN)):
		return "Not enough resources to build a wall segment."
	return ""

func can_place_segment(hex_a: Vector2i, hex_b: Vector2i) -> bool:
	return get_placement_error(hex_a, hex_b).is_empty()

## Every fresh segment starts at Wooden tier (design doc: "Wooden -> Brick ->
## Concrete") — upgrade_segment() is the only way to advance it from there.
func place_segment(hex_a: Vector2i, hex_b: Vector2i) -> WallSegment:
	var error := get_placement_error(hex_a, hex_b)
	if not error.is_empty():
		placement_rejected.emit(hex_a, hex_b, error)
		return null
	if _resource_manager:
		_resource_manager.spend(WallCatalog.get_build_cost(WallCatalog.WOODEN))
	return _register_segment(hex_a, hex_b, WallCatalog.WOODEN, _next_id, -1.0, true)

func _register_segment(hex_a: Vector2i, hex_b: Vector2i, tier: int, id: int, current_hp: float, advance_next_id: bool) -> WallSegment:
	var segment := WallSegment.new(hex_a, hex_b, tier, id, current_hp)
	if advance_next_id:
		_next_id = id + 1
	_segments.append(segment)
	wall_segment_placed.emit(segment)
	return segment

func get_upgrade_error(segment: WallSegment) -> String:
	if not segment:
		return "No such wall segment."
	if segment.is_breached():
		return "A breached wall segment must be repaired before it can be upgraded."
	if segment.tier >= WallCatalog.MAX_TIER:
		return "%s is already at its highest tier." % WallCatalog.get_display_name(segment.tier)
	var next_tier := segment.tier + 1
	if _tech_manager and not _tech_manager.is_wall_tier_unlocked(next_tier):
		return "%s hasn't been researched yet." % WallCatalog.get_display_name(next_tier)
	if _resource_manager and not _resource_manager.can_afford(WallCatalog.get_upgrade_cost(next_tier)):
		return "Not enough resources to upgrade to %s." % WallCatalog.get_display_name(next_tier)
	return ""

func can_upgrade_segment(segment: WallSegment) -> bool:
	return get_upgrade_error(segment).is_empty()

## Rebuilds the segment to the next tier's full spec — current_hp resets to
## the new tier's max_hp rather than carrying forward whatever fraction of
## damage it had, matching how a genuine reconstruction (not a patch-up)
## would work. Costs 50% of building that tier from scratch (design doc,
## decided), via WallCatalog.get_upgrade_cost().
func upgrade_segment(segment: WallSegment) -> bool:
	var error := get_upgrade_error(segment)
	if not error.is_empty():
		upgrade_rejected.emit(segment, error)
		return false
	var next_tier := segment.tier + 1
	if _resource_manager:
		_resource_manager.spend(WallCatalog.get_upgrade_cost(next_tier))
	segment.tier = next_tier
	segment.current_hp = segment.get_max_hp()
	wall_segment_upgraded.emit(segment)
	return true

func get_defense_work_error(segment: WallSegment, work_type: GameEnums.BuildingType) -> String:
	if not segment:
		return "No such wall segment."
	if work_type != GameEnums.BuildingType.DITCH and work_type != GameEnums.BuildingType.OIL_PIT:
		return "Unknown defense work."
	if work_type == GameEnums.BuildingType.DITCH and segment.has_ditch:
		return "This segment already has a Ditch."
	if work_type == GameEnums.BuildingType.OIL_PIT and segment.has_oil_pit:
		return "This segment already has an Oil Pit."
	var definition := BuildingCatalog.get_definition(work_type)
	if not definition:
		return "Unknown defense work."
	if _resource_manager and not _resource_manager.can_afford(definition.construction_cost):
		return "Not enough resources for %s." % definition.display_name
	return ""

func can_add_defense_work(segment: WallSegment, work_type: GameEnums.BuildingType) -> bool:
	return get_defense_work_error(segment, work_type).is_empty()

func add_defense_work(segment: WallSegment, work_type: GameEnums.BuildingType) -> bool:
	var error := get_defense_work_error(segment, work_type)
	if not error.is_empty():
		return false
	var definition := BuildingCatalog.get_definition(work_type)
	if _resource_manager:
		_resource_manager.spend(definition.construction_cost)
	if work_type == GameEnums.BuildingType.DITCH:
		segment.has_ditch = true
	else:
		segment.has_oil_pit = true
	defense_work_added.emit(segment, work_type)
	return true

## Exposed for Phase 5.4's CombatEngine / 5.10's horde siege AI to call once
## they exist — nothing calls this yet. A besieging horde's siege bonus and
## Ditches/Oil Pits actually inflicting counter-damage (design doc: "each
## adds toughness/breach-difficulty or inflicts damage on a besieging horde
## before/during a breach attempt") are documented as future inputs to
## whatever `amount` a combat resolution loop computes, not implemented
## here — there's no attacking horde or combat loop yet to compute one.
func damage_segment(segment: WallSegment, amount: float) -> void:
	if not segment or segment.is_breached():
		return
	segment.current_hp = maxf(segment.current_hp - amount, 0.0)
	wall_segment_damaged.emit(segment, amount)
	if segment.is_breached():
		wall_segment_breached.emit(segment)

## Exposed for SaveLoadManager (Phase 2.8) — WallSegment saves directly
## (see its own class doc comment for why it needs no separate save-entry
## wrapper, unlike BuildingInstance).
func get_save_state() -> Dictionary:
	return {"segments": _segments.duplicate(), "next_id": _next_id}

## Restoration bypasses _register_segment() (and so doesn't re-emit
## wall_segment_placed per segment) — nothing yet reacts to that signal for
## recompute purposes the way BuildingManager's placement signals drive ZoC/
## Fog of War, so a plain state replace is enough. Revisit if a future
## renderer needs a per-segment "just appeared" event on load.
func load_save_state(segments: Array[WallSegment], next_id: int) -> void:
	_segments = segments.duplicate()
	_next_id = next_id
