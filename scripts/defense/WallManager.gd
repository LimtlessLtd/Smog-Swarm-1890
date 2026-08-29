class_name WallManager
extends Node

## Runtime owner of every placed WallSegment. Mirrors BuildingManager's shape
## (validate -> spend -> register) and LogisticsNetwork's "chain of
## independently-tracked segments between hex pairs" shape — walls are the
## same idea, defensive instead of logistical, each segment carrying its OWN
## health pool rather than a shared network-wide state.
##
## Combat: HordeManager._siege_wall() calls damage_segment() below directly
## whenever a horde's drift path crosses an unbreached segment — this class
## stays combat-ignorant, same "manager mutates a passed-in Resource" split
## every other combat-adjacent class here keeps. repair_segment() is the
## recovery action a breach needs.

signal wall_segment_placed(segment: WallSegment)
signal wall_segment_upgraded(segment: WallSegment)
signal wall_segment_damaged(segment: WallSegment, amount: float)
signal wall_segment_breached(segment: WallSegment)
signal wall_segment_repaired(segment: WallSegment)
signal placement_rejected(hex_a: Vector2i, hex_b: Vector2i, reason: String)
signal upgrade_rejected(segment: WallSegment, reason: String)
signal repair_rejected(segment: WallSegment, reason: String)
signal repair_started(segment: WallSegment, days: int)  ## wall_segment_repaired (above) only fires once a queued repair job finishes.
signal wall_segment_removed(segment: WallSegment)
signal demolish_rejected(segment: WallSegment, reason: String)

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
@export var tech_manager_path: NodePath  ## Optional — gates upgrade_segment() against the Tech Tree. Unset means every wall tier reads as unlocked.
@export var logistics_network_path: NodePath  ## Optional — feeds is_legacy_segment()'s outer/inner classification. Unset means every segment reads as "outer".
@export var building_manager_path: NodePath  ## Optional — seed_starting_defenses() needs BuildingManager.get_starting_settlement_hexes() to know what to wall. Unset skips seeding entirely; the class stays usable without it.
@export var infestation_manager_path: NodePath  ## Optional — gates placement on design_doc.md §2.1's band. Unset means every hex reads as Cleared.

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _tech_manager: TechManager
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _infestation_manager: InfestationManager
var _segments: Array[WallSegment] = []
var _next_id: int = 1
var _pending_repair: Array[Dictionary] = []  ## Paid-for repairs not yet finished — {segment, days_remaining}.

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
	# get_node_or_null: InfestationManager is a LATER Main.tscn sibling (it has
	# to seed after BuildingManager's starting settlement), so the node exists
	# but has not run its own _ready() yet. seed_starting_defenses() below
	# therefore sees an unseeded manager and reads every hex as Cleared, which
	# is the right answer anyway — D7 puts the player's own hex at 0%.
	if infestation_manager_path != NodePath():
		_infestation_manager = get_node_or_null(infestation_manager_path) as InfestationManager
	TickManager.day_completed.connect(_on_day_completed)

## Mirrors BuildingManager's own construction/repair queue processing shape.
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

func get_segments_at(coord: Vector2i) -> Array[WallSegment]:
	var result: Array[WallSegment] = []
	for segment in _segments:
		if segment.connects(coord):
			result.append(segment)
	return result

## "The wall between these two hexes" isn't a single lookup — a wall is a
## chain of independent <=100m pieces along a player-drawn line, not one
## piece per hex edge; a single edge can hold anywhere from zero to dozens
## of pieces. Returns the first unbreached piece whose own line
## (point_a-point_b) genuinely intersects the travel segment
## (from_world -> to_world), via Geometry2D.segment_intersects_segment().
## Restricted to pieces registered under from_hex/to_hex (WallSegment.connects())
## for efficiency — a piece can only block a crossing near the specific
## hex(es) its own endpoints fall in.
##
## `ignore_gates` is what makes a Gate a gate. The player's own units pass
## it (true), a horde does not (false, the default) — "friendly military
## units can pass through gates with no problems, zombies cannot pass
## through gates" (user report). Before this, a Gate blocked a unit's route
## exactly like solid wall, which left gates with no function at all on the
## player's side and could seal a garrison inside its own starting
## perimeter. A gate still SIEGES identically (damage_segment() has never
## looked at is_gate) — this is a movement rule, not a combat one.
## When `ignore_gates` is true and a usable gate stands on this edge, the
## line tested is the one the mover WILL ACTUALLY WALK -- from `from_world`
## to the gate -- not the straight `from_world`->`to_world` line.
##
## Found by diagnosing a player report that units could not leave a hex they
## had walled and gated on every side (2026-08-20). A gate only ever helped
## if it happened to straddle the exact hex-centre-to-hex-centre line: the
## mover is aimed at the gate by UnitOrderController._crossing_offset()
## (via get_gate_crossing_offset() below), but the route was tested against
## the centre line instead, so ANY solid piece sitting on that centre line
## refused an edge the unit would have walked through the gate. Measured on
## the reported save: the single terrain-passable, water-free direction out
## of the unit's hex had a gate on it and was still refused, by one solid
## piece on the centre line -- sealing the unit into its own hex.
##
## Both callers that matter (HexPathfinder.find_path()'s neighbour expansion
## and UnitOrderController._blocked_by_wall()'s per-crossing re-check) go
## through this one function, so they keep asking the identical question --
## the live-lock _blocked_by_wall()'s own doc comment warns about needs them
## to agree, and re-aiming here moves both at once.
func get_blocking_segment(from_hex: Vector2i, to_hex: Vector2i, from_world: Vector2, to_world: Vector2, ignore_gates: bool = false) -> WallSegment:
	var candidates := get_segments_at(from_hex)
	if to_hex != from_hex:
		for segment in get_segments_at(to_hex):
			if not candidates.has(segment):
				candidates.append(segment)
	var travel_to := to_world
	if ignore_gates and to_hex != from_hex:
		var gate_offset: Variant = get_gate_crossing_offset(from_hex, to_hex)
		if gate_offset != null:
			travel_to = HexCoord.axial_to_world(to_hex) + gate_offset
	for segment in candidates:
		if ignore_gates and segment.is_gate:
			continue
		if not segment.is_breached() and Geometry2D.segment_intersects_segment(from_world, travel_to, segment.point_a, segment.point_b) != null:
			return segment
	return null

func get_next_id() -> int:
	return _next_id

## "Legacy" (inner ring) is a purely positional classification derived live
## from Zone of Control coverage, not a stored WallSegment field — a segment
## is legacy once BOTH hexes it connects carry ZoC coverage, meaning some
## other edge (another wall, or distance) now stands between it and any
## unclaimed ground. A segment with at least one uncovered end is still
## "outer": the currently exposed defensive line. Territory shifting
## (recapture, ZoC recompute) can flip this live, same as ZoC itself.
##
## Not a new combat concept — an "inner" segment blocks and sieges exactly
## like an "outer" one, same WallCatalog HP/tier math for both. The fallback-
## bulkhead behavior falls out for free from HordeManager._advance_horde()'s
## existing per-edge peek, which re-checks for an unbreached WallSegment on
## EVERY hex boundary a horde's path crosses — a horde that breaches an
## outer segment and keeps walking its route simply hits whatever the next
## edge holds, an inner ring included. This method exists purely so a
## renderer (StrategicOverlayManager's wall markers) can tell the two apart;
## it changes nothing about how either behaves in combat.
##
## No LogisticsNetwork wired means no distinction is knowable — every
## segment reads as "outer". A short (<=100m) piece's own two endpoints
## often land in the SAME hex (hexes are ~5000m across) rather than two
## different adjacent ones — hex_a == hex_b in that case means "both ends of
## this piece are inside one hex," and the legacy check collapses to that
## single hex's own coverage.
func is_legacy_segment(segment: WallSegment) -> bool:
	if not _logistics_network or not segment:
		return false
	var covered := _logistics_network.get_covered_hexes()
	if segment.hex_a == segment.hex_b:
		return covered.has(segment.hex_a)
	return covered.has(segment.hex_a) and covered.has(segment.hex_b)

## Returns "" if a single wall PIECE can legally be placed with its own
## endpoints at point_a/point_b right now, or a rejection reason otherwise.
## Called once per chopped piece by place_wall_line(), not once per whole
## drawn line.
##
## No "already defends this edge" duplicate check: preventing two freehand
## pieces from overlapping is a genuinely harder 2D "do these line segments
## cross or run parallel within some tolerance" problem, not a hex-pair
## lookup, and overlapping pieces are wasteful but harmless, not a
## correctness bug.
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
	# design_doc.md §2.1: a wall IS the Defensive Tier, so Fringe allows it and
	# Contested/Hive Core do not. Checked on BOTH endpoint hexes because a
	# freehand piece straddles a border — the alternative, picking one, would
	# let a player wall into a Hive Core by drawing from the safe side.
	# A drawn line crossing a band boundary therefore places some pieces and
	# rejects others, exactly as place_wall_line() already does for terrain.
	var infestation_error := _infestation_error(cell_a, cell_b)
	if not infestation_error.is_empty():
		return infestation_error
	if _resource_manager and not _resource_manager.can_afford(_cost_for_length(tier, point_a.distance_to(point_b))):
		return "Not enough resources to build this wall piece."
	return ""

func can_place_wall_piece(point_a: Vector2, point_b: Vector2, tier: int = WallCatalog.WOODEN) -> bool:
	return get_placement_error_for_points(point_a, point_b, tier).is_empty()

## design_doc.md §2.1's Build Rights for a wall piece: "" when both of the hexes
## it touches allow one, otherwise a rejection naming the offending hex's own
## percentage. Empty when no InfestationManager is wired, so a fixture without
## one reads every hex as Cleared rather than as unbuildable.
func _infestation_error(cell_a: HexCell, cell_b: HexCell) -> String:
	if not _infestation_manager:
		return ""
	for cell: HexCell in [cell_a, cell_b]:
		var band := _infestation_manager.band_at(cell.coord)
		if band == GameEnums.InfestationBand.CONTESTED or band == GameEnums.InfestationBand.HIVE_CORE:
			return "Cannot build a wall at %.0f%% infestation — clear the zombies out first." % _infestation_manager.infestation_at(cell.coord)
	return ""

## Cost scales with a piece's own real length — a "segment" is a short
## player-drawn chunk (<=100m) rather than a fixed whole-hex-edge span. The
## flat WallCatalog.get_build_cost(tier)/get_repair_cost(tier)/get_upgrade_cost(tier)
## prices are implicitly "per one hex edge" (HexCoord.HEX_SIZE world units
## long); dividing by that gives a stable cost-per-world-unit rate, so a
## full-length drawn wall costs about what a one-piece-per-edge wall used to
## in total, spread across many small, individually cheap pieces. Max HP is
## NOT scaled the same way — WallSegment.get_max_hp() still returns the
## tier's full value per piece (matches *They Are Billions*' own model):
## cheap-but-tough small pieces, where a long drawn wall's TOTAL toughness
## scales up with how much of it you build, not just its cost.
static func _cost_for_length(tier: int, length: float) -> Dictionary:
	return _scaled_by_length(WallCatalog.get_build_cost(tier), length)

## Shared by build/repair/upgrade costs — see _cost_for_length()'s own doc
## comment for the length-scale-cost-but-not-HP reasoning.
static func _scaled_by_length(cost: Dictionary, length: float) -> Dictionary:
	var fraction := length / HexCoord.HEX_SIZE
	var scaled: Dictionary = {}
	for resource_type in cost:
		scaled[resource_type] = float(cost[resource_type]) * fraction
	return scaled

func _segment_length(segment: WallSegment) -> float:
	return segment.point_a.distance_to(segment.point_b)

## The real placement entry point — freehand click-drag, chopped into
## independently-placed, independently-HP'd pieces no longer than
## WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS each, validating and paying
## for every piece individually. A piece that fails validation (dips into
## impassable terrain) is skipped rather than aborting the whole drawn line.
## Returns every piece actually placed (empty if none were).
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

## Where a gate anchored at `anchor` and aimed at `toward` actually ends.
## Static and public so WallPlacementController's preview draws the exact
## piece place_gate() would build — a preview that is merely "about right"
## is worse than none, because the player aims with it.
##
## Length is fixed at WallCatalog.GATE_LENGTH_WORLD_UNITS: the cursor picks
## the DIRECTION only. A gate is one manufactured object, not a run of wall
## drawn to taste.
static func gate_endpoint(anchor: Vector2, toward: Vector2) -> Vector2:
	var direction := toward - anchor
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT  ## Degenerate aim (cursor exactly on the anchor) — any direction beats a zero-length gate.
	return anchor + direction.normalized() * WallCatalog.GATE_LENGTH_WORLD_UNITS

## Places ONE gate, at its own fixed length, aimed from `anchor` toward
## `toward`. Deliberately NOT routed through place_wall_line(): that chops
## anything longer than MAX_SEGMENT_LENGTH_WORLD_UNITS into independent
## pieces, which for a gate would mean three separately-breachable thirds of
## a door and three copies of the gate art laid end to end. Returns the
## placed segment, or null if the ground rejected it (the caller reports the
## reason, which placement_rejected has already carried).
func place_gate(anchor: Vector2, toward: Vector2, tier: int = WallCatalog.WOODEN) -> WallSegment:
	if not _hex_grid_map:
		return null
	var end := gate_endpoint(anchor, toward)
	var error := get_placement_error_for_points(anchor, end, tier)
	if not error.is_empty():
		placement_rejected.emit(_hex_grid_map.world_to_coord(anchor), _hex_grid_map.world_to_coord(end), error)
		return null
	if _resource_manager:
		_resource_manager.spend(_cost_for_length(tier, anchor.distance_to(end)))
	return _register_freehand_segment(anchor, end, tier, true)

## The point a unit should aim at to cross from `from_hex` into `to_hex`
## when a Gate stands on that edge, as an offset from `to_hex`'s own centre
## (the same shape SubHexPortalGraph.portal_offset_for_step() returns, so a
## caller substitutes one for the other). Null when no usable gate is there.
##
## Without this a unit walks at the sub-hex portal instead and crosses the
## defensive line wherever that lands — visually straight through the solid
## wall beside its own gate. Breached gates are skipped: a hole in the line
## is not somewhere to aim, and the wall either side of it is what a unit
## still has to get around.
## `get_segments_at()` returns every segment touching a hex, on ANY of its
## six edges, so "nearest gate to this boundary" alone will happily return a
## gate standing on a completely different side of the hex and aim a mover at
## it. A gate on THIS edge lies within half an edge length of that edge's own
## midpoint (a pointy-top hex's side equals its circumradius, HexCoord.HEX_SIZE),
## so anything past that is on another edge and must not answer for this one.
## Without this bound, get_blocking_segment() above would re-aim a crossing at
## an unrelated gate and open an edge that has no gate at all.
const _GATE_ON_EDGE_RADIUS: float = HexCoord.HEX_SIZE * 0.5

func get_gate_crossing_offset(from_hex: Vector2i, to_hex: Vector2i) -> Variant:
	var boundary := (HexCoord.axial_to_world(from_hex) + HexCoord.axial_to_world(to_hex)) * 0.5
	var best: WallSegment = null
	var best_distance := _GATE_ON_EDGE_RADIUS
	for segment in get_segments_at(from_hex) + get_segments_at(to_hex):
		if not segment.is_gate or segment.is_breached():
			continue
		var midpoint := (segment.point_a + segment.point_b) * 0.5
		var distance := midpoint.distance_to(boundary)
		if distance < best_distance:
			best_distance = distance
			best = segment
	if not best:
		return null
	return (best.point_a + best.point_b) * 0.5 - HexCoord.axial_to_world(to_hex)

## Free/seeded placement (seed_starting_defenses()) — same chopping as
## place_wall_line() but bypasses the cost check and never spends resources.
## Terrain/map-bounds validity is still checked so a malformed core-hex
## boundary doesn't silently place pieces off the map.
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

## Walls the OUTER boundary of BuildingManager.get_starting_settlement_hexes()
## with a free Wooden segment on every edge crossing from a core hex to a
## non-core, passable one. An edge BETWEEN two core hexes is skipped (it's
## interior ground once both sides are "inside"). Free the same way every
## other piece of the opening move is (bypasses the cost check, registered
## directly) — this is the game's own starting state, not a player purchase.
##
## A subset of boundary edges carry a Gate in the middle of an otherwise
## solid run. The ring stops hordes AND the player's own units
## (get_blocking_segment()), so without a gate the starting garrison would
## be sealed inside its own free perimeter — a plain gap instead would be a
## hole a horde walks through uncontested. A Gate still sieges like any
## other segment, just at a fraction of the HP. Each DISTINCT source hex's own first boundary edge
## is reserved as solid (not just one global reservation) — a global
## reservation only guarantees one solid wall total, which can leave an
## entire disconnected ring at 100% Gates if a different ring's own edges
## consume the whole shared reservation first.
##
## No-op if segments already exist (a loaded save has its own wall state) or
## if the dependencies aren't wired. Runs from _ready(), which fires after
## BuildingManager's own _ready() as long as this stays a later Main.tscn sibling.
const _STARTING_WALL_GATE_COUNT: int = 2

func seed_starting_defenses() -> void:
	if not _segments.is_empty() or not _hex_grid_map or not _building_manager:
		return
	var core_hexes := _building_manager.get_starting_settlement_hexes()
	if core_hexes.is_empty():
		return
	var core_set: Dictionary = {}  # Vector2i -> true, O(1) "is this hex inside the perimeter"
	for coord in core_hexes:
		core_set[coord] = true

	var boundary_edges: Array[Vector2i] = []  # outside-hex half of each (core_hex, outside_hex) pair, paired 1:1 with boundary_sources
	var boundary_sources: Array[Vector2i] = []
	var boundary_directions: Array[int] = []  # Which of the six HexCoord.NEIGHBOR_DIRECTIONS the pair sits on — identifies the shared EDGE, see _seed_boundary_edge().
	var seen_edges: Dictionary = {}  # String ("q,r-q,r") -> true — dedup within this pass
	for core_coord in core_hexes:
		for direction_index in range(6):
			var neighbor: Vector2i = core_coord + HexCoord.NEIGHBOR_DIRECTIONS[direction_index]
			if core_set.has(neighbor):
				continue  ## Interior edge between two core hexes — not a boundary.
			var cell := _hex_grid_map.get_cell(neighbor)
			if not cell or not cell.is_passable():
				continue
			# Two DIFFERENT core hexes can share the same outside neighbor —
			# canonicalize by sorting the pair so both directions hash to the
			# same key.
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
			boundary_directions.append(direction_index)

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
		_seed_boundary_edge(boundary_sources[i], boundary_directions[i], gate_indices.has(i))

## Seeds one boundary edge: a chain of <=100m wall pieces laid ALONG THE
## SHARED HEX EDGE, with a single Gate centred on it when `with_gate`.
##
## Along the edge, not from hex centre to hex centre. The old version drew
## the wall down the line between the two centres — i.e. along the direction
## anything crossing would be travelling, not across it. That is not a
## perimeter, and it does not block: get_blocking_segment() asks whether the
## travel line intersects the wall's line, and Geometry2D.segment_intersects_segment()
## reports nothing for two collinear segments, so a horde walking straight
## down that edge passed through its own free starting wall untouched. Laid
## across the boundary, a crossing meets it square and the intersection is
## unambiguous.
##
## The gate goes in the MIDDLE of the edge because that is exactly where a
## centre-to-centre crossing passes through it — which is what makes
## get_gate_crossing_offset() able to aim a unit at a door rather than at a
## wall. The rest of the edge is ordinary solid wall: a gate is a door in a
## line, not a whole open side.
##
## `corners[direction_index]/[direction_index + 1]` is NOT the edge facing
## `HexCoord.NEIGHBOR_DIRECTIONS[direction_index]`: `corner_points()`'s corner
## i sits at world angle `60*i - 30`, so its edge i faces `60*i`, while
## `NEIGHBOR_DIRECTIONS[i]` faces `-60*i` — opposite senses, coinciding only at
## i = 0 and 3 and mirror-swapped (1<->5, 2<->4) otherwise. `k = (6 - i) % 6`
## is the edge that actually faces NEIGHBOR_DIRECTIONS[i]; verified for all six
## by scripts/test/check_corner_neighbor_alignment.gd. Seeding has no
## production caller (only verify_gates.gd), so this was never a live defect —
## it is corrected here so the test fixture models real geometry.
func _seed_boundary_edge(core_coord: Vector2i, direction_index: int, with_gate: bool) -> void:
	var corners := HexCoord.corner_points(HexCoord.axial_to_world(core_coord))
	var edge_index := (6 - direction_index) % 6
	var edge_a: Vector2 = corners[edge_index]
	var edge_b: Vector2 = corners[(edge_index + 1) % 6]
	if not with_gate:
		_seed_wall_line(edge_a, edge_b, WallCatalog.WOODEN, false)
		return
	var midpoint := (edge_a + edge_b) * 0.5
	var along := (edge_b - edge_a).normalized()
	var half_gate := along * WallCatalog.GATE_LENGTH_WORLD_UNITS * 0.5
	_seed_wall_line(edge_a, midpoint - half_gate, WallCatalog.WOODEN, false)
	_seed_gate(midpoint - half_gate, midpoint + half_gate)
	_seed_wall_line(midpoint + half_gate, edge_b, WallCatalog.WOODEN, false)

## The gate half of _seed_boundary_edge(), free and un-chopped — the same
## "validate terrain, skip rather than fail" contract _seed_wall_line() has.
func _seed_gate(point_a: Vector2, point_b: Vector2) -> void:
	var cell_a := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_a))
	var cell_b := _hex_grid_map.get_cell(_hex_grid_map.world_to_coord(point_b))
	if not cell_a or not cell_b or not cell_a.is_passable() or not cell_b.is_passable():
		return
	_register_freehand_segment(point_a, point_b, WallCatalog.WOODEN, true)

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

## current_hp resets to the new tier's max_hp rather than carrying forward
## whatever fraction of damage it had, matching a genuine reconstruction
## (not a patch-up). Costs 50% of building that tier from scratch, via
## WallCatalog.get_upgrade_cost().
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

func damage_segment(segment: WallSegment, amount: float) -> void:
	if not segment or segment.is_breached():
		return
	segment.current_hp = maxf(segment.current_hp - amount, 0.0)
	wall_segment_damaged.emit(segment, amount)
	if segment.is_breached():
		wall_segment_breached.emit(segment)

## Restores to the segment's OWN current tier's full health (not an upgrade
## — same tier, just fixed). Cost is WallCatalog.get_repair_cost() — 50% of
## building that tier from scratch, same fraction upgrade_segment() uses.
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

## Pays upfront, finishes later — the segment stays breached (still-red,
## still passable to a horde) until _on_day_completed() applies the actual
## restoration `days` days from now.
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

## Refunds HALF of what this piece would cost to build fresh at its own
## current tier/length (_cost_for_length() — the same derived-not-stored
## cost every other wall action here recomputes on demand), except any
## ENERGY entry, refunded in FULL. Checked per-resource-type (unlike
## BuildingHealthController's building version, which refunds Energy as a
## separate top-up) because a wall's build-cost dict has no structural
## guarantee against holding an ENERGY entry — no WallCatalog tier actually
## prices ENERGY today, so this is a no-op in practice, but doesn't hardcode
## that assumption.
func get_demolish_error(segment: WallSegment) -> String:
	if not segment:
		return "No such wall segment."
	return ""

func can_demolish_segment(segment: WallSegment) -> bool:
	return get_demolish_error(segment).is_empty()

func demolish_segment(segment: WallSegment) -> bool:
	var error := get_demolish_error(segment)
	if not error.is_empty():
		demolish_rejected.emit(segment, error)
		return false
	if _resource_manager:
		var cost := _cost_for_length(segment.tier, _segment_length(segment))
		for resource_type in cost:
			var fraction := 1.0 if resource_type == GameEnums.ResourceType.ENERGY else 0.5
			_resource_manager.add(resource_type, float(cost[resource_type]) * fraction)
	_remove_segment(segment)
	return true

## Also purges any queued _pending_repair job for this segment, same
## "don't leave a dangling job pointing at nothing" fix
## BuildingManager.remove_building() applies for the same reason.
func _remove_segment(segment: WallSegment) -> void:
	_segments.erase(segment)
	_pending_repair = _pending_repair.filter(func(job: Dictionary) -> bool: return job["segment"] != segment)
	wall_segment_removed.emit(segment)

func get_save_state() -> Dictionary:
	return {"segments": _segments.duplicate(), "next_id": _next_id}

## Bypasses _register_freehand_segment() (doesn't re-emit wall_segment_placed
## per segment) — nothing reacts to that signal for recompute purposes the
## way BuildingManager's placement signals drive ZoC/Fog of War, so a plain
## state replace is enough.
func load_save_state(segments: Array[WallSegment], next_id: int) -> void:
	_segments = segments.duplicate()
	_next_id = next_id
