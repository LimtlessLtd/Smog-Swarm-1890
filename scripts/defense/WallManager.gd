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
## User report ("repairing... should take some amount of time") —
## wall_segment_repaired (above) now only fires once a queued job finishes.
signal repair_started(segment: WallSegment, days: int)

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
## Optional — gates upgrade_segment() against Phase 2.9's Tech Tree. Unset
## means every wall tier is treated as unlocked (no tech-gate check).
@export var tech_manager_path: NodePath
## Optional — feeds is_legacy_segment()'s outer/inner classification (Phase
## 4.1). Unset means every segment reads as "outer" (today's pre-4.1-decision
## look), same "gracefully skip it" convention as tech_manager_path above.
@export var logistics_network_path: NodePath
## Optional — start-of-game pass (user request): seed_starting_defenses()
## below needs to know where BuildingManager.seed_starting_buildings() put
## the free Town Hall, so it can wall that hex in. Unset skips seeding
## entirely (same "gracefully skip it" convention as every other optional
## dependency here) — this class stays fully usable without it, same as
## before this pass, for any test/scene that doesn't wire one up.
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _segments: Array[WallSegment] = []
var _next_id: int = 1
## Paid-for repairs not yet finished — {segment, days_remaining}. Same known
## save/load gap as BuildingManager's/UnitManager's own equivalent queues
## (flagged on theirs, not repeated per-file).
var _pending_repair: Array[Dictionary] = []

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	seed_starting_defenses()
	TickManager.day_completed.connect(_on_day_completed)

## Ticks every queued repair down by one day, applying the actual HP
## restoration and firing wall_segment_repaired once it reaches zero —
## mirrors BuildingManager._process_pending_repair()'s own shape.
func _on_day_completed(_day_number: int) -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_repair:
		job["days_remaining"] -= 1
		var segment: WallSegment = job["segment"]
		if job["days_remaining"] <= 0:
			segment.current_hp = segment.get_max_hp()
			wall_segment_repaired.emit(segment)
		else:
			still_pending.append(job)
	_pending_repair = still_pending

func get_segments() -> Array[WallSegment]:
	return _segments.duplicate()

## **Removed (freehand wall rework): `get_segment_between(hex_a, hex_b)`.**
## "The wall between these two hexes" stopped being a meaningful question
## once a wall became a chain of independent <=100m pieces along a
## player-drawn line rather than one piece per hex edge — a single edge
## can now hold anywhere from zero to dozens of pieces, or none at all if
## the drawn line only clips a corner of it. `get_blocking_segment()` below
## is the real replacement for HordeManager's siege lookup (the one actual
## caller this had); `get_placement_error_for_points()` no longer has an
## "already defends this edge" dedup check at all — see that function's own
## doc comment for why overlap-prevention was deliberately dropped rather
## than ported forward as a wrong, edge-shaped approximation of a
## genuinely 2D "do these two line segments overlap" problem.

func get_segments_at(coord: Vector2i) -> Array[WallSegment]:
	var result: Array[WallSegment] = []
	for segment in _segments:
		if segment.connects(coord):
			result.append(segment)
	return result

## Real replacement for the old get_segment_between()-based siege lookup —
## HordeManager._advance_horde()'s "peek before crossing" (see its own doc
## comment) now needs "does ANY unbreached piece actually cross this
## horde's real travel line," not "is there THE piece between these two
## hexes," since several independent pieces can now sit along or near one
## hex boundary. Returns the first unbreached piece whose own line
## (point_a-point_b) genuinely intersects the travel segment
## (from_world -> to_world), via Godot's own Geometry2D.segment_intersects_segment()
## rather than hand-rolled line math. Restricted to pieces registered
## under `from_hex`/`to_hex` (WallSegment.connects(), same as
## get_segments_at() above) for efficiency — a piece can only ever block a
## crossing near the specific hex(es) its own endpoints actually fall in,
## the same spatial-index role hex_a/hex_b already played before this
## rework, just geometry-checked now instead of assumed from the hex pair
## alone.
func get_blocking_segment(from_hex: Vector2i, to_hex: Vector2i, from_world: Vector2, to_world: Vector2) -> WallSegment:
	var candidates := get_segments_at(from_hex)
	if to_hex != from_hex:
		for segment in get_segments_at(to_hex):
			if not candidates.has(segment):
				candidates.append(segment)
	for segment in candidates:
		if not segment.is_breached() and Geometry2D.segment_intersects_segment(from_world, to_world, segment.point_a, segment.point_b) != null:
			return segment
	return null

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
## **Freehand rework note:** a short (<=100m) piece's own two endpoints
## often land in the SAME hex (hexes are ~5000m across) rather than two
## different adjacent ones the way a whole-edge segment always used to —
## `hex_a == hex_b` in that case just means "both ends of this piece are
## inside one hex," and the legacy check collapses to that single hex's
## own coverage rather than requiring two.
func is_legacy_segment(segment: WallSegment) -> bool:
	if not _logistics_network or not segment:
		return false
	var covered := _logistics_network.get_covered_hexes()
	if segment.hex_a == segment.hex_b:
		return covered.has(segment.hex_a)
	return covered.has(segment.hex_a) and covered.has(segment.hex_b)

## Returns "" if a single wall PIECE can legally be placed with its own
## endpoints at `point_a`/`point_b` right now, or a human-readable
## rejection reason otherwise — mirrors BuildingManager.get_placement_error()'s
## "queryable without side effects" pattern. Called once per chopped piece
## by place_wall_line() below, not once per whole drawn line.
##
## **Deliberately no "already defends this edge" duplicate check anymore**
## (the old hex-pair version had one, via the now-removed
## get_segment_between()). Preventing two freehand pieces from overlapping
## is a genuinely different, harder 2D "do these line segments cross or
## run parallel within some tolerance" problem, not a hex-pair lookup —
## and *They Are Billions* itself doesn't strictly prevent overlapping/
## adjacent wall placement either (its own "no more than two rows deep"
## rule is a different, depth-limiting constraint, not an anti-overlap
## one). Out of scope for this pass: overlapping pieces are wasteful but
## harmless, not a correctness bug.
func get_placement_error_for_points(point_a: Vector2, point_b: Vector2, tier: int = WallCatalog.WOODEN) -> String:
	if not _hex_grid_map:
		return "No hex grid map wired to WallManager."
	if point_a.distance_to(point_b) <= 0.01:
		return "A wall piece needs two different points."
	var cell_a := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_a))
	var cell_b := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_b))
	if not cell_a or not cell_b:
		return "Wall piece is outside the map."
	if not cell_a.is_passable() or not cell_b.is_passable():
		return "Cannot wall off marsh or peat bog until it is drained."
	if _resource_manager and not _resource_manager.can_afford(_cost_for_length(tier, point_a.distance_to(point_b))):
		return "Not enough resources to build this wall piece."
	return ""

func can_place_wall_piece(point_a: Vector2, point_b: Vector2, tier: int = WallCatalog.WOODEN) -> bool:
	return get_placement_error_for_points(point_a, point_b, tier).is_empty()

## Cost scales with a piece's own real length now that a "segment" is a
## short player-drawn chunk (player spec: <=100m) rather than a fixed
## whole-hex-edge span — the OLD flat WallCatalog.get_build_cost(tier)/
## get_repair_cost(tier)/get_upgrade_cost(tier) prices were implicitly
## "per one hex edge" (HexCoord.HEX_SIZE world units long, the single
## piece a whole edge used to be). Dividing by that gives a stable
## cost-per-world-unit rate, so a full-length drawn wall costs about what
## the old one-piece-per-edge wall used to in total — spread across many
## small, individually cheap pieces — instead of every ~10-unit piece
## independently costing the OLD whole-edge price (which would have
## inflated a full drawn perimeter's total cost by ~50x for no reason
## connected to the actual bug being fixed). **Max HP is deliberately NOT
## scaled the same way** — WallSegment.get_max_hp() still returns the
## tier's full value per piece, matching *They Are Billions*' own real
## model (confirmed via research): each small placed piece is fully as
## tough as its tier implies, not a fraction of it: cheap-but-tough small
## pieces, where a long drawn wall's TOTAL toughness genuinely scales up
## with how much of it you build, not just its cost.
static func _cost_for_length(tier: int, length: float) -> Dictionary:
	return _scaled_by_length(WallCatalog.get_build_cost(tier), length)

## Shared by build/repair/upgrade costs alike — see _cost_for_length()'s
## own doc comment for the full "why length-scale cost but not HP"
## reasoning; this is just the generic form so get_repair_error()/
## upgrade_segment() below can apply the exact same scaling to THEIR own
## flat per-tier WallCatalog costs against a specific segment's own length,
## not just fresh-build cost.
static func _scaled_by_length(cost: Dictionary, length: float) -> Dictionary:
	var fraction := length / HexCoord.HEX_SIZE
	var scaled: Dictionary = {}
	for resource_type in cost:
		scaled[resource_type] = float(cost[resource_type]) * fraction
	return scaled

## A segment's own real length — point_a/point_b are its actual placement
## geometry now (freehand rework), so this is a plain distance, not
## anything hex-derived.
static func _segment_length(segment: WallSegment) -> float:
	return segment.point_a.distance_to(segment.point_b)

## **The real placement entry point (player report: walls should be "free
## hand to place/draw," matching *They Are Billions*' own click-drag
## model, plus "no longer than 100 meters MAXIMUM... split up into
## multiple segments" beyond that).** Chops the straight line from
## `world_a` to `world_b` (wherever the player actually dragged) into
## independently-placed, independently-HP'd pieces no longer than
## `WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS` each, validating and
## paying for every piece individually — a piece that fails validation
## (dips into impassable terrain, say) is simply skipped rather than
## aborting the whole drawn line, so one bad stretch doesn't waste an
## otherwise-good drag. Returns every piece actually placed (empty if
## none were, e.g. the whole line was invalid or unaffordable).
func place_wall_line(world_a: Vector2, world_b: Vector2, tier: int = WallCatalog.WOODEN, is_gate: bool = false) -> Array[WallSegment]:
	var placed: Array[WallSegment] = []
	if not _hex_grid_map:
		return placed
	var total_length := world_a.distance_to(world_b)
	if total_length <= 0.01:
		return placed
	var piece_count := maxi(1, ceili(total_length / WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS))
	for i in range(piece_count):
		var point_a := world_a.lerp(world_b, float(i) / float(piece_count))
		var point_b := world_a.lerp(world_b, float(i + 1) / float(piece_count))
		var error := get_placement_error_for_points(point_a, point_b, tier)
		if not error.is_empty():
			placement_rejected.emit(_hex_grid_map.world_to_coord(point_a), _hex_grid_map.world_to_coord(point_b), error)
			continue
		if _resource_manager:
			_resource_manager.spend(_cost_for_length(tier, point_a.distance_to(point_b)))
		placed.append(_register_freehand_segment(point_a, point_b, tier, is_gate))
	return placed

## Free/seeded placement (seed_starting_defenses() below) — same chopping
## as place_wall_line() but bypasses get_placement_error_for_points()'s
## cost check entirely and never spends resources, same "this is the
## game's own starting state, not a player purchase" framing
## seed_starting_defenses() itself already documents. Terrain/map-bounds
## validity is still worth checking (a malformed core-hex boundary
## shouldn't silently place pieces off the map), so this reuses the same
## per-piece error check, just ignores an affordability-only rejection.
func _seed_wall_line(world_a: Vector2, world_b: Vector2, tier: int, is_gate: bool) -> void:
	var total_length := world_a.distance_to(world_b)
	if total_length <= 0.01:
		return
	var piece_count := maxi(1, ceili(total_length / WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS))
	for i in range(piece_count):
		var point_a := world_a.lerp(world_b, float(i) / float(piece_count))
		var point_b := world_a.lerp(world_b, float(i + 1) / float(piece_count))
		var cell_a := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_a))
		var cell_b := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_b))
		if not cell_a or not cell_b or not cell_a.is_passable() or not cell_b.is_passable():
			continue
		_register_freehand_segment(point_a, point_b, tier, is_gate)

func _register_freehand_segment(point_a: Vector2, point_b: Vector2, tier: int, is_gate: bool = false) -> WallSegment:
	var hex_a := _hex_grid_map.world_to_coord(point_a)
	var hex_b := _hex_grid_map.world_to_coord(point_b)
	var segment := WallSegment.new(hex_a, hex_b, point_a, point_b, tier, _next_id, -1.0, is_gate)
	_next_id += 1
	_segments.append(segment)
	wall_segment_placed.emit(segment)
	return segment

## Start-of-game pass (user request: "start the game with an iron foundry
## already inside a set of walls", extended a pass later to "extend the
## starting walls so [the Farm is] within the perimeter too"). Walls the
## OUTER boundary of BuildingManager.get_starting_settlement_hexes() — Town
## Hall + Foundry's own hex, plus the Farm and its connecting corridor when
## one was found — with a free Wooden segment on every edge that crosses
## from a core hex to a non-core, passable one. An edge BETWEEN two core
## hexes is deliberately skipped (it's interior ground once both sides are
## "inside", not a boundary to defend) — get_segment_between() is the dedup
## guard for the genuinely rare case where two core hexes share a common
## outside neighbor and would otherwise both try to wall the same edge.
## Free the same way every other piece of this opening move is (bypasses
## get_placement_error()'s cost check entirely, registered directly) — this
## is the game's own starting state, not a player purchase.
##
## A subset of those boundary edges are Gates instead of solid wall (see
## WallSegment.is_gate) rather than left as bare unwalled gaps: the whole
## ring would only ever block a HORDE anyway (walls never block the
## player's own units/logistics — see HexPathfinder's own doc comment), so
## a plain gap wouldn't be "protecting an opening", it would just be a hole
## a horde walks through uncontested. A Gate still sieges like any other
## segment, just at a fraction of the HP — a deliberately weaker point, not
## an undefended one. `- 1` below reserves at least one solid (non-gate)
## segment whenever there's more than one boundary edge at all — found by
## actually booting the game and inspecting a real seeded result: Manchester
## alone only ever has 2 walled edges (4 of its 6 neighbors are impassable
## Chat Moss peat bog), and a fixed gate count with no such reservation
## silently turned both into Gates, leaving ~0 real defensive value.
##
## Guarded the same way BuildingManager.seed_starting_buildings() guards
## itself: a no-op if segments already exist (a loaded save already has its
## own, real wall state) or if the dependencies this needs aren't wired.
## Runs from _ready(), which fires after BuildingManager's own _ready() as
## long as this node stays a LATER Main.tscn sibling (already true — see
## DiscontentManager's own doc comment for the same ordering requirement).
const _STARTING_WALL_GATE_COUNT: int = 2

func seed_starting_defenses() -> void:
	if not _segments.is_empty() or not _hex_grid_map or not _building_manager:
		return
	var core_hexes := _building_manager.get_starting_settlement_hexes()
	if core_hexes.is_empty():
		return
	var core_set: Dictionary = {}  # Vector2i -> true, for O(1) "is this hex inside the perimeter" checks
	for coord in core_hexes:
		core_set[coord] = true

	var boundary_edges: Array[Vector2i] = []  # outside-hex half of each (core_hex, outside_hex) pair, paired 1:1 with boundary_sources below
	var boundary_sources: Array[Vector2i] = []
	var seen_edges: Dictionary = {}  # String (canonical "q,r-q,r" key) -> true — dedup WITHIN this pass; get_segment_between() can't help here since nothing is actually registered until the loop below runs.
	for core_coord in core_hexes:
		for neighbor in HexCoord.neighbors(core_coord):
			if core_set.has(neighbor):
				continue  ## Interior edge between two core hexes — not a boundary.
			var cell := _hex_grid_map.get_cell(neighbor)
			if not cell or not cell.is_passable():
				continue
			# Two DIFFERENT core hexes can share the same outside neighbor
			# (common in a hex grid) — canonicalize by sorting the pair so
			# both directions hash to the same key.
			var a := core_coord
			var b := neighbor
			if b.x < a.x or (b.x == a.x and b.y < a.y):
				var tmp := a
				a = b
				b = tmp
			var key := "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
			if seen_edges.has(key):
				continue
			seen_edges[key] = true
			boundary_sources.append(core_coord)
			boundary_edges.append(neighbor)

	# Reserve each DISTINCT source hex's own first boundary edge as solid —
	# not just one global reservation across the whole perimeter — so the
	# disclosed "farm unreachable, two separate compounds" fallback above
	# can't repeat the exact bug the single-hex version of this method
	# already hit once: a global "- 1" only guarantees ONE solid wall
	# total, which silently left an entire disconnected ring (Town Hall's
	# own 2-edge one) at 100% Gates when the Farm's own 4-edge ring
	# consumed the whole shared reservation instead.
	var gate_eligible_indices: Array[int] = []
	var reserved_source: Dictionary = {}  # Vector2i -> true, one reservation per distinct source hex
	for i in boundary_edges.size():
		var source := boundary_sources[i]
		if not reserved_source.has(source):
			reserved_source[source] = true
			continue
		gate_eligible_indices.append(i)

	var gate_count := mini(_STARTING_WALL_GATE_COUNT, gate_eligible_indices.size())
	var gate_indices: Dictionary = {}
	for i in range(gate_count):
		gate_indices[gate_eligible_indices[i]] = true

	for i in boundary_edges.size():
		# Freehand rework: each boundary EDGE now seeds as a chain of
		# <=100m pieces (via _seed_wall_line(), hex-center to hex-center —
		# the same line the old single whole-edge segment used to run
		# along) rather than one giant piece, same as any player-drawn
		# wall now would. gate_indices is still keyed per EDGE, not per
		# piece — every piece along a "gate" edge seeds as a Gate, which
		# reads as one long weak stretch rather than a single-tile weak
		# point; a deliberate simplification, not a bug, since the
		# starting perimeter's own gate count/spacing was already a
		# placeholder balancing choice before this rework.
		_seed_wall_line(HexCoord.axial_to_world(boundary_sources[i]), HexCoord.axial_to_world(boundary_edges[i]), WallCatalog.WOODEN, gate_indices.has(i))

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
	if _resource_manager and not _resource_manager.can_afford(_scaled_by_length(WallCatalog.get_upgrade_cost(next_tier), _segment_length(segment))):
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
		_resource_manager.spend(_scaled_by_length(WallCatalog.get_upgrade_cost(next_tier), _segment_length(segment)))
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
	if _resource_manager and not _resource_manager.can_afford(_scaled_by_length(WallCatalog.get_repair_cost(segment.tier), _segment_length(segment))):
		return "Not enough resources to repair this wall segment."
	return ""

func can_repair_segment(segment: WallSegment) -> bool:
	return get_repair_error(segment).is_empty()

## Same "pay upfront, finish later" shape BuildingManager.repair_building()
## now uses — see that function's own doc comment. The segment stays
## breached (still-red, still passable to a horde) until
## _on_day_completed() above applies the actual restoration `days` days
## from now.
func repair_segment(segment: WallSegment) -> bool:
	var error := get_repair_error(segment)
	if not error.is_empty():
		repair_rejected.emit(segment, error)
		return false
	if _resource_manager:
		_resource_manager.spend(_scaled_by_length(WallCatalog.get_repair_cost(segment.tier), _segment_length(segment)))
	var days := segment.tier + 1
	_pending_repair.append({"segment": segment, "days_remaining": days})
	repair_started.emit(segment, days)
	return true

## Exposed for SaveLoadManager (Phase 2.8) — WallSegment saves directly
## (see its own class doc comment for why it needs no separate save-entry
## wrapper, unlike BuildingInstance).
func get_save_state() -> Dictionary:
	return {"segments": _segments.duplicate(), "next_id": _next_id}

## Restoration bypasses _register_freehand_segment() (and so doesn't re-emit
## wall_segment_placed per segment) — nothing yet reacts to that signal for
## recompute purposes the way BuildingManager's placement signals drive ZoC/
## Fog of War, so a plain state replace is enough. Revisit if a future
## renderer needs a per-segment "just appeared" event on load.
func load_save_state(segments: Array[WallSegment], next_id: int) -> void:
	_segments = segments.duplicate()
	_next_id = next_id
