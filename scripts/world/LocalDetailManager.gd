class_name LocalDetailManager
extends Node2D

## Orchestrates the Strategic <-> Tactical hard-cut zoom switch. Listens for
## CameraController crossing its tactical_zoom_threshold, then hydrates a
## small neighborhood of hexes around wherever the camera is centered into
## full TacticalHexView detail — and only for hexes that qualify as settled/
## frontier (see _hex_qualifies_for_detail); distant unclaimed wilderness
## stays an abstract HexCellView tile even at max zoom, which is what keeps
## this affordable for a map the size of Great Britain.
##
## Parented as a sibling of HexGridMap under WorldRoot (not under Main like
## other systems) specifically so its spawned TacticalHexViews share
## HexGridMap's local coordinate space and render on top of it by plain
## sibling draw order — added after HexGridMap in Main.tscn.
##
## Also tracks CameraController's internal Tactical fidelity band
## (GameEnums.TacticalFidelity) and pushes it to every hydrated
## TacticalHexView — a hex hydrating fresh picks up whatever band is
## current, an already-hydrated one updates live as the camera zooms
## deeper within Tactical view.

## Hex disk radius hydrated around the camera — now computed LIVE off the
## camera's actual visible world extent (_current_detail_radius()) rather
## than a fixed constant. User report: "it looks like we are only checking
## if we can see the center of a hex tile before displaying the sub hex
## tile biomes, instead we should be checking if we can see any part of the
## hex tile" — the real mechanism was a fixed radius-1 disk (7 hexes)
## around whichever hex the camera's center point falls in, entirely
## decoupled from viewport size or zoom: near tactical_zoom_threshold (the
## LEAST zoomed-in end of Tactical), a full viewport can show on the order
## of 80-100 hexes, so the great majority of what's visible fell back to a
## flat, sub-hex-detail-free tile. _hex_qualifies_for_detail() already
## bounds the EXPENSIVE part of hydration (buildings; the square ground's
## real-terrain compositing until that was removed, after which ground stopped
## being per-hex at all) to settled/frontier/ZoC-covered hexes regardless
## of how big this radius is, so widening it mostly just means the cheap
## qualification check runs over more candidates — the two constants below
## are a floor (never less generous than the old fixed behavior) and a
## ceiling (bounds worst-case cost in a late-game, ZoC-saturated colony,
## where a genuinely large fraction of the wider radius COULD qualify).
const MIN_DETAIL_RADIUS: int = 1
const MAX_DETAIL_RADIUS: int = 8

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var logistics_network_path: NodePath
@export var camera_path: NodePath
@export var fog_of_war_path: NodePath
@export var wall_manager_path: NodePath  ## Optional — Tactical-zoom wall rendering. Unset means walls don't render up close; StrategicOverlayManager's own thin markers are unaffected.
@export var unit_command_controller_path: NodePath  ## Optional — selection-highlight sync. Unset means TacticalHexView's per-building tint never lights up.
## Optional — repaints a hex whose sub-hex ground actually changed under it
## (a founded settlement paving its urban disc). Unset means a newly founded
## or newly grown town's ground only updates on the next building change
## there. See _on_urban_extent_changed() for why the building signals this
## class already listens to aren't sufficient on their own.
@export var settlement_founding_controller_path: NodePath
## Optional — the scatter props (trees/rocks/etc.) this class forwards to
## UnitOrderController/HordeManager as steering obstacles via
## get_props_at(). Unset means those two see no obstacles at all, which is
## the same thing that used to happen for any hex that was not hydrated.
@export var terrain_detail_view_path: NodePath

var _hex_grid_map: HexGridMap
var _terrain_detail_view: TerrainDetailView
var _building_manager: BuildingManager
var _logistics_network: LogisticsNetwork
var _camera: CameraController
var _fog_of_war: FogOfWarManager
var _wall_manager: WallManager
var _unit_command_controller: UnitCommandController
var _selected_building: BuildingInstance  ## Cached copy of _unit_command_controller.get_selected_building() as of the last _process() poll — see _process()'s own doc comment for why this is polled, not signal-driven.

var _is_tactical_mode: bool = false
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH  ## Pushed to every hydrated TacticalHexView; see _on_fidelity_changed().
var _last_centered_coord: Vector2i = Vector2i.ZERO
var _last_detail_radius: int = MIN_DETAIL_RADIUS  ## Change-detection cache for _process() only — _refresh_hydrated_neighborhood() itself always recomputes fresh via _current_detail_radius(), so every OTHER call site (building/fog/ZoC signals) stays correct without needing to know about zoom at all.
var _tactical_views: Dictionary = {}  # Vector2i -> TacticalHexView
var _wall_layer: Node2D
var _wall_markers: Dictionary = {}  # int (WallSegment.id) -> Line2D

func _ready() -> void:
	if terrain_detail_view_path != NodePath():
		_terrain_detail_view = get_node(terrain_detail_view_path)
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
		_building_manager.building_ruined.connect(_on_building_ruined)
		# building_placed fires the moment construction STARTS, so the hex
		# already re-hydrates with the grey construction tint at that point;
		# this is the matching hook for when it FINISHES, so the tint drops
		# off without a second building_placed emission (which would
		# double-fire every other building_placed listener too).
		_building_manager.building_construction_completed.connect(_on_buildings_changed)
	if settlement_founding_controller_path != NodePath():
		var founding: SettlementFoundingController = get_node(settlement_founding_controller_path)
		founding.urban_extent_changed.connect(_on_urban_extent_changed)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.network_recomputed.connect(_on_network_recomputed)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		_camera.tactical_fidelity_changed.connect(_on_fidelity_changed)
		_fidelity = _camera.get_tactical_fidelity()
	if fog_of_war_path != NodePath():
		_fog_of_war = get_node(fog_of_war_path)
		_fog_of_war.fog_state_changed.connect(_on_fog_state_changed)
	if unit_command_controller_path != NodePath():
		_unit_command_controller = get_node(unit_command_controller_path)

	_wall_layer = Node2D.new()
	_wall_layer.name = "TacticalWallLayer"
	_wall_layer.visible = false  # Only ever shown while _is_tactical_mode — see _on_tactical_mode_changed().
	# Kept as the LAST child of this node (_hydrate_hex()'s own move_child()
	# call re-enforces this on every hydration) rather than given a positive
	# z_index: z_index is a GLOBAL sort key across the whole 2D scene, not
	# scoped to this node's own children — a positive z_index here would
	# also out-rank TacticalEntityLayer/UnitCommandController's selection
	# ring/BuildPlacementController's ghost preview, every one a separate,
	# LATER sibling of LocalDetailManager under WorldRoot deliberately
	# ordered so units/zombies/UI draw on top of terrain. Re-parenting keeps
	# this layer at the SAME z_index (0) as everything else, so it only ever
	# wins the plain sibling-order tiebreak against its own TacticalHexView
	# siblings, never against a different node entirely.
	add_child(_wall_layer)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.wall_segment_placed.connect(_on_wall_segment_placed)
		_wall_manager.wall_segment_upgraded.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_breached.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_repaired.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_removed.connect(_on_wall_segment_removed)
		for segment in _wall_manager.get_segments():
			_on_wall_segment_placed(segment)

## Selection-highlight sync is polled here rather than signal-driven:
## UnitCommandController only emits building_instance_selected when a
## building becomes selected and selection_cleared when nothing is
## selected — selecting a UNIT or a WALL instead also silently clears
## _selected_building internally without emitting either signal. Comparing
## get_selected_building() against the last-known value catches all three
## cases uniformly with one check. Runs every frame regardless of tactical
## mode (unlike the hydration refresh below) so _selected_building stays
## correct even while zoomed out.
func _process(_delta: float) -> void:
	if _unit_command_controller:
		var selected := _unit_command_controller.get_selected_building()
		if selected != _selected_building:
			_apply_selected_building_change(_selected_building, selected)
			_selected_building = selected

	if not _is_tactical_mode or not _hex_grid_map or not _camera:
		return
	var centered_coord := _hex_grid_map.world_to_coord(_camera.global_position)
	var radius := _current_detail_radius()
	# Panning (coord changed) is the common trigger; a PURE zoom (radius
	# changed with the camera otherwise stationary) needs its own check —
	# zooming out while centered on the same hex still needs MORE hexes
	# covered, and that wouldn't otherwise fire a refresh at all.
	if centered_coord != _last_centered_coord or radius != _last_detail_radius:
		_last_centered_coord = centered_coord
		_last_detail_radius = radius
		_refresh_hydrated_neighborhood(centered_coord)

## The hex-disk radius that covers the camera's own current visible world
## extent, floored/ceilinged by MIN_DETAIL_RADIUS/MAX_DETAIL_RADIUS — see
## that constant's own doc comment. Same screen_size/zoom math
## MinimapView._draw_viewport_frame() already uses for the identical
## question ("how much world is actually on screen right now").
func _current_detail_radius() -> int:
	if not _camera or not _camera.is_inside_tree():
		return MIN_DETAIL_RADIUS
	var screen_size := _camera.get_viewport().get_visible_rect().size
	var half_world_extent := screen_size / _camera.zoom / 2.0
	# hex_disk() is a hexagonal region, a viewport is rectangular — using the
	# LARGER of the two half-extents over-covers the shorter axis's corners
	# rather than under-covering the longer axis's edges, a simpler estimate
	# than a real rectangular hex-region query for what's still just a
	# coverage bound, not exact geometry.
	var half_extent := maxf(half_world_extent.x, half_world_extent.y)
	var hex_spacing := sqrt(3.0) * HexCoord.HEX_SIZE  ## Real center-to-center neighbor distance (HexCoord.axial_to_world()'s own formula) — NOT HexCoord.HEX_SIZE itself, the hex's circumradius.
	var radius := int(ceil(half_extent / hex_spacing)) + 1  ## +1 so a hex only partially on-screen at the edge still hydrates, instead of popping in only once fully centered.
	return clampi(radius, MIN_DETAIL_RADIUS, MAX_DETAIL_RADIUS)

## Pushes the tint change to whichever hydrated TacticalHexView owns each
## building — a no-op for a hex that isn't currently hydrated (selecting a
## building means its hex WAS hydrated at click time, but the camera can
## pan away and dehydrate it while the selection persists; _selected_building
## stays correct regardless so the highlight reappears if that hex rehydrates).
func _apply_selected_building_change(previous: BuildingInstance, current: BuildingInstance) -> void:
	if previous:
		var previous_view: TacticalHexView = _tactical_views.get(previous.hex_coord)
		if previous_view:
			previous_view.set_building_selected(previous, false)
	if current:
		var current_view: TacticalHexView = _tactical_views.get(current.hex_coord)
		if current_view:
			current_view.set_building_selected(current, true)

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	_is_tactical_mode = is_tactical
	_wall_layer.visible = is_tactical  ## Strategic keeps its own thin StrategicOverlayManager markers; this thicker layer is Tactical-only.
	if not is_tactical:
		_dehydrate_all()
		return
	if _hex_grid_map and _camera:
		_last_centered_coord = _hex_grid_map.world_to_coord(_camera.global_position)
	_refresh_hydrated_neighborhood(_last_centered_coord)

func _hex_qualifies_for_detail(coord: Vector2i) -> bool:
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return false
	# An UNSEEN hex has nothing known to draw, at any zoom — it must be at
	# least EXPLORED before Tactical detail hydrates.
	if _fog_of_war and not _fog_of_war.is_at_least_explored(coord):
		return false
	if cell.is_settlement:
		return true
	if _building_manager and not _building_manager.get_buildings_at(coord).is_empty():
		return true
	if _logistics_network:
		var zoc := _logistics_network.get_zoc_state(coord)
		if zoc.has_military_coverage() or zoc.has_civilian_coverage:
			return true
	return false

## Forwarded to TerrainDetailView, which owns the scatter now — this class
## used to generate its own per-hex props and hand them to TacticalHexView,
## but that scatter was per macro hex and only existed on settled/frontier
## ground (see TerrainDetailView for both problems). Kept as a forward rather
## than repointing UnitOrderController/HordeManager, so the two callers keep
## asking the manager that owns hex hydration rather than growing a second
## NodePath into a rendering layer.
##
## Returns [] with no detail view wired, or for a hex whose terrain chunk is
## not streamed — prop avoidance only applies near the camera, which is also
## the only place a player can see it happen.
func get_props_at(coord: Vector2i) -> Array[PropInstance]:
	return _terrain_detail_view.get_props_at(coord) if _terrain_detail_view else []

func _refresh_hydrated_neighborhood(center: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for coord in HexCoord.hex_disk(center, _current_detail_radius()):
		if _hex_qualifies_for_detail(coord):
			wanted[coord] = true

	for coord in _tactical_views.keys():
		if not wanted.has(coord):
			_dehydrate_hex(coord)
	for coord in wanted:
		if not _tactical_views.has(coord):
			_hydrate_hex(coord)

func _hydrate_hex(coord: Vector2i) -> void:
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	var buildings: Array[BuildingInstance] = []
	if _building_manager:
		buildings = _building_manager.get_buildings_at(coord)
	var fog_state := GameEnums.FogState.VISIBLE
	if _fog_of_war:
		fog_state = _fog_of_war.get_fog_state(coord)
	var zoc_state: ZoneOfControlState = null
	if _logistics_network:
		zoc_state = _logistics_network.get_zoc_state(coord)
	var view := TacticalHexView.new()
	view.setup(cell, buildings, fog_state, _fidelity, zoc_state, _selected_building)
	add_child(view)
	# Keep _wall_layer as the LAST child of THIS node — add_child() above
	# always appends, which would otherwise push _wall_layer back behind
	# this freshly-hydrated hex's own ground/buildings on every hydration.
	move_child(_wall_layer, get_child_count() - 1)
	_tactical_views[coord] = view

func _dehydrate_hex(coord: Vector2i) -> void:
	var view: TacticalHexView = _tactical_views.get(coord)
	if view:
		view.queue_free()
	_tactical_views.erase(coord)

func _dehydrate_all() -> void:
	for coord in _tactical_views.keys():
		_dehydrate_hex(coord)

## Placing/removing a building can change what an already-hydrated hex looks
## like, or whether it should be hydrated at all. _refresh_hydrated_neighborhood()
## alone only adds/removes hexes it doesn't already have a view for, so an
## already-hydrated hex's stale view needs an explicit tear-down first to
## pick up the change.
func _on_buildings_changed(instance: BuildingInstance) -> void:
	if not _is_tactical_mode:
		return
	if _tactical_views.has(instance.hex_coord):
		_dehydrate_hex(instance.hex_coord)
	_refresh_hydrated_neighborhood(_last_centered_coord)

## A ruin doesn't change WHICH buildings exist at a hex, only how one of
## them looks — the same dehydrate/rehydrate _on_buildings_changed() does is
## a valid (if heavier-handed) way to pick that up.
func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	_on_buildings_changed(instance)

## A founded settlement's urban disc always moves as a CONSEQUENCE of a
## building event on that same hex (a Town Hall completing, or housing
## changing what its population sums to), so the building signals above
## already fire for every case this one does — but they fire FIRST:
## SettlementFoundingController is a child of Main while this class is a
## child of WorldRoot, Main's first child, so its _ready() (and therefore
## its own connection to the same building signal) runs after this one's.
## Rehydrating off the building signal alone would rebuild the view from
## terrain the disc hadn't been written to yet. Listening here instead makes
## the repaint order-independent rather than resting on _ready() order.
func _on_urban_extent_changed(coord: Vector2i, _radius: float) -> void:
	if not _is_tactical_mode or not _tactical_views.has(coord):
		return
	_dehydrate_hex(coord)
	_refresh_hydrated_neighborhood(_last_centered_coord)

## A ZoC change can flip an already-hydrated hex's own overlay without that
## hex newly qualifying/disqualifying for detail at all (e.g. a Garrison
## two hexes away extending Military coverage in here) — push the new state
## to every currently-hydrated view directly, same "update live" precedent
## _on_fog_state_changed() sets, rather than relying solely on
## _refresh_hydrated_neighborhood()'s own add/remove-only pass.
func _on_network_recomputed() -> void:
	if _logistics_network:
		for coord in _tactical_views:
			_tactical_views[coord].set_zoc_state(_logistics_network.get_zoc_state(coord))
	if _is_tactical_mode:
		_refresh_hydrated_neighborhood(_last_centered_coord)

## Pushes the new band to every currently-hydrated hex in place
## (TacticalHexView.set_fidelity() no-ops/skips a redraw if nothing
## changed) — no dehydrate/rehydrate needed, same "update live" precedent
## _on_fog_state_changed() sets for fog.
func _on_fidelity_changed(fidelity: GameEnums.TacticalFidelity) -> void:
	_fidelity = fidelity
	for view: TacticalHexView in _tactical_views.values():
		view.set_fidelity(fidelity)

## An already-hydrated hex just needs its dimming updated live (EXPLORED
## <-> VISIBLE); a newly-EXPLORED hex that wasn't hydrated before (was
## UNSEEN, blocked by _hex_qualifies_for_detail) may now qualify, so the
## neighborhood still needs a refresh either way.
func _on_fog_state_changed(coord: Vector2i, state: GameEnums.FogState) -> void:
	if _tactical_views.has(coord):
		_tactical_views[coord].set_fog_state(state)
	if _is_tactical_mode:
		_refresh_hydrated_neighborhood(_last_centered_coord)

## --- Tactical-zoom wall rendering -------------------------------------------
##
## Mirrors WallMarkerRenderer's own shape (a Line2D from hex_a's world
## center to hex_b's, recolored in place on placed/upgraded/breached/
## repaired) — same geometry is correct at any zoom, a wall runs between two
## hex centers through their shared edge. The only real difference is the
## width: WallVisuals.line_width() is tuned to read at Strategic's
## zoomed-way-out scale and would be a hairline against a 512-unit Tactical
## hex, so this uses WallVisuals.tactical_width() — the width the strip art
## is authored to be drawn at. No fog-of-war/hydration gating (matching StrategicOverlayManager's
## own precedent for walls — a wall is always the player's own construction,
## nothing to spot about your own perimeter): _wall_layer's own visibility
## (Tactical-mode-only) is enough gating.
func _on_wall_segment_placed(segment: WallSegment) -> void:
	var marker := _build_wall_marker(segment)
	_wall_layer.add_child(marker)
	_wall_markers[segment.id] = marker

func _on_wall_segment_state_changed(segment: WallSegment) -> void:
	var marker: Line2D = _wall_markers.get(segment.id)
	if marker:
		_apply_wall_segment_look(marker, segment)

func _on_wall_segment_removed(segment: WallSegment) -> void:
	var marker: Line2D = _wall_markers.get(segment.id)
	if marker:
		marker.queue_free()
	_wall_markers.erase(segment.id)

func _build_wall_marker(segment: WallSegment) -> Line2D:
	var body := Line2D.new()
	_apply_wall_segment_look(body, segment)
	return body

## Art, tiling mode, tint and geometry all come from
## WallVisuals.apply_segment_look() — the Strategic marker and the placement
## preview call the same function, so a wall cannot look like one thing here
## and another there (they had already drifted: only one of the three used
## to set texture_repeat, without which LINE_TEXTURE_TILE clamps to the
## texture's edge pixels instead of repeating). Only the WIDTH is this
## class's own decision, and only legacy dimming is layered on afterwards.
func _apply_wall_segment_look(body: Line2D, segment: WallSegment) -> void:
	WallVisuals.apply_segment_look(body, segment, WallVisuals.tactical_width(segment.is_breached()))
	var is_legacy := _wall_manager != null and _wall_manager.is_legacy_segment(segment)
	body.modulate = WallVisuals.legacy_modulate() if is_legacy else WallVisuals.outer_modulate()
