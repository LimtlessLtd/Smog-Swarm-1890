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
## Combat is real now: `HordeManager._siege_wall()` (Phase 4.1/5.10) calls
## `damage_segment()` below directly whenever a horde's own drift path
## crosses an unbreached segment, with a siege-damage bonus and Ditch/Oil
## Pit counter-damage folded in on that caller's side — this class itself
## stays combat-ignorant, same "manager mutates a passed-in Resource"
## split every other combat-adjacent class here keeps. `repair_segment()`
## is the recovery action a real breach now needs.

signal wall_segment_placed(segment: WallSegment)
signal wall_segment_upgraded(segment: WallSegment)
signal wall_segment_damaged(segment: WallSegment, amount: float)
signal wall_segment_breached(segment: WallSegment)
signal wall_segment_repaired(segment: WallSegment)
signal defense_work_added(segment: WallSegment, work_type: GameEnums.BuildingType)
signal placement_rejected(hex_a: Vector2i, hex_b: Vector2i, reason: String)
signal upgrade_rejected(segment: WallSegment, reason: String)
signal repair_rejected(segment: WallSegment, reason: String)

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
## Optional — gates upgrade_segment() against Phase 2.9's Tech Tree. Unset
## means every wall tier is treated as unlocked (no tech-gate check).
@export var tech_manager_path: NodePath
## Optional — feeds is_legacy_segment()'s outer/inner classification (Phase
## 4.1). Unset means every segment reads as "outer" (today's pre-4.1-decision
## look), same "gracefully skip it" convention as tech_manager_path above.
@export var logistics_network_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _logistics_network: LogisticsNetwork
var _segments: Array[WallSegment] = []
var _next_id: int = 1

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)

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

## Design doc Phase 4.1: "retain legacy inner walls as fallback bulkheads
## during breach events" — **decided:** this is a purely POSITIONAL
## classification derived live from Zone of Control coverage
## (LogisticsNetwork, Phase 2.3), not a new stored WallSegment field. A
## segment is "legacy" (an inner ring — once the frontier, now fully
## enclosed by the settlement's own controlled ground) once BOTH the hexes
## it connects carry ZoC coverage, meaning some other edge — another wall,
## or simply distance — now stands between it and any unclaimed ground. A
## segment with at least one uncovered end is still "outer": the currently
## exposed defensive line. Territory shifting (Phase 5.8 loss/recapture,
## ZoC recompute) means this can and does flip live, same as ZoC itself.
##
## Deliberately NOT a new combat concept — an "inner" segment blocks and
## sieges exactly like an "outer" one, same WallCatalog HP/tier math for
## both. The actual fallback-bulkhead BEHAVIOR the design doc asks for
## already falls out for free from HordeManager._advance_horde()'s existing
## per-edge peek, which re-checks for an unbreached WallSegment on EVERY hex
## boundary a horde's path crosses, not just the first one — a horde that
## breaches an outer segment and keeps walking its pre-planned route simply
## hits whatever the next edge holds, an inner ring included, and sieges it
## the same way. Verified, not just assumed (see this phase's own todo.md
## note). This method exists purely so a renderer (StrategicOverlayManager's
## wall markers, Phase 2.7.3) — or a future wall-selection UI — can tell the
## two apart; it changes nothing about how either one behaves in combat.
##
## No LogisticsNetwork wired means no distinction is knowable — every
## segment reads as "outer", the same "gracefully skip it" fallback every
## other optional dependency here already uses.
func is_legacy_segment(segment: WallSegment) -> bool:
	if not _logistics_network or not segment:
		return false
	var covered := _logistics_network.get_covered_hexes()
	return covered.has(segment.hex_a) and covered.has(segment.hex_b)

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

## Design doc Phase 4.1/4.2: the recovery action a breach genuinely needs
## now that Phase 5.10's `HordeManager` can actually inflict one
## (`_siege_wall()`) — `upgrade_segment()`'s own `get_upgrade_error()`
## already anticipated this ("a breached wall segment must be repaired
## before it can be upgraded"), but nothing implemented repair itself until
## now. Restores to the segment's OWN current tier's full health (not an
## upgrade — same tier, just fixed), for `WallCatalog.get_repair_cost()`
## (50% of building that tier from scratch, same fraction
## `upgrade_segment()` already uses).
func get_repair_error(segment: WallSegment) -> String:
	if not segment:
		return "No such wall segment."
	if not segment.is_breached():
		return "This wall segment isn't breached."
	if _resource_manager and not _resource_manager.can_afford(WallCatalog.get_repair_cost(segment.tier)):
		return "Not enough resources to repair this wall segment."
	return ""

func can_repair_segment(segment: WallSegment) -> bool:
	return get_repair_error(segment).is_empty()

func repair_segment(segment: WallSegment) -> bool:
	var error := get_repair_error(segment)
	if not error.is_empty():
		repair_rejected.emit(segment, error)
		return false
	if _resource_manager:
		_resource_manager.spend(WallCatalog.get_repair_cost(segment.tier))
	segment.current_hp = segment.get_max_hp()
	wall_segment_repaired.emit(segment)
	return true

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
