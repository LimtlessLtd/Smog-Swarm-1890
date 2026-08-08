class_name MinimapView
extends Control

## Phase 6.1's "Always-visible minimap of the Strategic layer ... while
## zoomed into Tactical view" (design doc). **Decided (interpreting the
## doc's own stated justification — "the hard-cut zoom otherwise leaves the
## player with zero awareness of anything happening elsewhere on the map
## while zoomed into one hex cluster"):** shown only while
## CameraController.is_tactical_zoom() is true, not in both view modes —
## Strategic view already IS the full map, so a minimap of it there would
## be redundant chrome rather than restoring lost awareness. Same
## "show/hide off tactical_mode_changed" wiring StrategicOverlayManager
## already uses, just inverted (that one hides during Tactical, this one
## shows only during Tactical).
##
## Code-drawn placeholder (a single _draw() call), same convention as every
## other visual in this project — reuses TerrainVisuals/FogVisuals/
## BuildingVisuals directly rather than a fourth copy of any of their color
## logic, so this agrees with the Strategic/Tactical views it's a miniature
## of. Non-uniform stretch (world bounds mapped independently on X/Y into a
## fixed-size panel, no aspect-ratio letterboxing) — a simplification
## appropriate to placeholder fidelity, not real cartography.
##
## Performance: terrain+building content only redraws off
## FogOfWarManager.fog_state_changed / BuildingManager.building_placed/
## _removed (rare events), matching LogisticsNetwork/FogOfWarManager's own
## "recompute on the signal, not every frame" precedent — this can't afford
## to re-walk every hex on the map 60 times a second. The one thing that
## DOES need to track continuously, the camera-viewport frame, redraws off
## a modest fixed-interval Timer instead of every frame — smooth enough to
## feel live while panning, far cheaper than full framerate.
##
## Spotted-horde markers (design doc 2.7.6) are deliberately NOT drawn here
## — that marker system itself doesn't exist yet (blocked on Phase 5.3
## reconnaissance; see todo.md's own 2.7.6 entry). This draws what
## StrategicOverlayManager already draws today (buildings) plus terrain,
## not a superset invented just for the minimap.
##
## **Threat Meter (design doc Phase 6.1), implemented here:** "an indicator
## per sector showing horde attraction levels, visible on the hex overview
## map" — this minimap IS that overview map. A translucent diamond marker
## (shape-distinct from the plain square hex dots and circular building
## dots already drawn here, same "never color alone" accessibility rule
## every other marker in this project follows) at every hex
## `NoiseManager.get_noise_at()` reports as nonzero, sized AND colored by
## intensity (amber, low, small -> red, high, large) via one shared lerp —
## two independent visual cues for the same value, not just a color ramp.
## Same fog gate as building icons (at-least-EXPLORED, not full VISIBLE) —
## a noise source is the player's own industry, already-known territory
## works the same way a building icon already does here.

const VIEWPORT_REFRESH_SECONDS: float = 0.1
const HEX_DOT_HALF_SIZE: float = 1.5   ## Minimap-space pixels, not world-space — every hex draws as the same small flat square regardless of actual hex size.
const BUILDING_DOT_RADIUS: float = 2.5
const BACKGROUND_COLOR: Color = Color("#1f150f")
const BORDER_COLOR: Color = Color("#cfa24e")
const VIEWPORT_FRAME_COLOR: Color = Color("#f4e7c5")

## Threat Meter marker radius bounds — minimap-space pixels, not world
## units (see NoiseVisuals.gd for the shared color/intensity curve this
## scales against, also used by StrategicOverlayManager's own world-view
## copy of the same overlay).
const THREAT_MARKER_RADIUS_MIN: float = 2.0
const THREAT_MARKER_RADIUS_MAX: float = 6.0

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _fog_of_war_manager: FogOfWarManager
var _noise_manager: NoiseManager
var _camera: CameraController

var _panel_size: Vector2 = Vector2.ZERO
var _world_bounds_min: Vector2 = Vector2.ZERO
var _world_bounds_size: Vector2 = Vector2.ONE

## `panel_size` is passed in explicitly rather than read back from this
## Control's own `size` — MainHUD's own layout-helper doc comment already
## flags Control.size/get_combined_minimum_size() as able to read stale on
## the same frame a Control is first positioned; an explicit fixed size
## sidesteps that class of bug entirely rather than risking hitting it again.
##
## `noise_manager` is optional — same "gracefully skip it" convention every
## other optional dependency in this project follows; unset just means no
## Threat Meter markers, everything else here is unaffected.
func setup(hex_grid_map: HexGridMap, building_manager: BuildingManager, fog_of_war_manager: FogOfWarManager, camera: CameraController, panel_size: Vector2, noise_manager: NoiseManager = null) -> void:
	_hex_grid_map = hex_grid_map
	_building_manager = building_manager
	_fog_of_war_manager = fog_of_war_manager
	_camera = camera
	_panel_size = panel_size
	_noise_manager = noise_manager

	_compute_world_bounds()

	if _fog_of_war_manager:
		_fog_of_war_manager.fog_state_changed.connect(_on_fog_state_changed)
	if _building_manager:
		_building_manager.building_placed.connect(_on_building_changed)
		_building_manager.building_removed.connect(_on_building_changed)
	if _noise_manager:
		_noise_manager.noise_recomputed.connect(_on_noise_recomputed)
	DisplaySettings.changed.connect(_on_display_settings_changed)
	if _camera:
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		visible = _camera.is_tactical_zoom()

	var refresh_timer := Timer.new()
	refresh_timer.wait_time = VIEWPORT_REFRESH_SECONDS
	refresh_timer.autostart = true
	add_child(refresh_timer)
	refresh_timer.timeout.connect(_on_viewport_refresh)

	queue_redraw()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical
	if is_tactical:
		queue_redraw()  ## Content may be stale from while hidden (buildings placed, fog changed, elsewhere on the map).

func _on_fog_state_changed(_coord: Vector2i, _state: GameEnums.FogState) -> void:
	if visible:
		queue_redraw()

## Design doc (user request): "add options so we can enable and disable the
## overlays" — DisplaySettings.show_threat_meter_minimap is the only flag
## this class itself consults (terrain/buildings/viewport frame aren't
## "overlays" in the sense being toggled here, they're the minimap's own
## baseline content). A blanket redraw on ANY flag changing (not just this
## one) is simplest and cheap enough at this scale — same "just redraw,
## don't bother diffing which flag actually changed" reasoning
## fog_state_changed/building_changed already lean on.
func _on_display_settings_changed() -> void:
	if visible:
		queue_redraw()

func _on_building_changed(_instance: BuildingInstance) -> void:
	if visible:
		queue_redraw()

func _on_noise_recomputed() -> void:
	if visible:
		queue_redraw()

func _on_viewport_refresh() -> void:
	if visible:
		queue_redraw()

func _compute_world_bounds() -> void:
	if not _hex_grid_map:
		return
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for cell in _hex_grid_map.get_all_cells():
		var world_pos := HexCoord.axial_to_world(cell.coord)
		min_x = minf(min_x, world_pos.x)
		min_y = minf(min_y, world_pos.y)
		max_x = maxf(max_x, world_pos.x)
		max_y = maxf(max_y, world_pos.y)
	if min_x == INF:
		return  ## No cells generated yet — keep the ZERO/ONE defaults so later division-by-zero can't happen.
	# Padded by one hex's own footprint so edge tiles aren't drawn flush
	# against the panel border.
	var pad := HexCoord.HEX_SIZE
	_world_bounds_min = Vector2(min_x - pad, min_y - pad)
	_world_bounds_size = Vector2(max_x - min_x + pad * 2.0, max_y - min_y + pad * 2.0)

func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var normalized := (world_pos - _world_bounds_min) / _world_bounds_size
	return normalized * _panel_size

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _panel_size), BACKGROUND_COLOR)
	if not _hex_grid_map:
		return

	if _fog_of_war_manager:
		for cell in _hex_grid_map.get_all_cells():
			var fog_state := _fog_of_war_manager.get_fog_state(cell.coord)
			if fog_state == GameEnums.FogState.UNSEEN:
				continue  ## Never scouted — the minimap shouldn't leak information the main view wouldn't either.
			var pos := _world_to_minimap(HexCoord.axial_to_world(cell.coord))
			var color := TerrainVisuals.biome_color(cell.biome_type, cell.soil_fertility) * FogVisuals.tint_color(fog_state)
			draw_rect(Rect2(pos - Vector2.ONE * HEX_DOT_HALF_SIZE, Vector2.ONE * HEX_DOT_HALF_SIZE * 2.0), color)

	if _building_manager:
		for instance in _building_manager.get_all_buildings():
			if _fog_of_war_manager and not _fog_of_war_manager.is_at_least_explored(instance.hex_coord):
				continue
			var pos := _world_to_minimap(HexCoord.axial_to_world(instance.hex_coord))
			draw_circle(pos, BUILDING_DOT_RADIUS, BuildingVisuals.category_color(instance.definition.category))

	_draw_threat_markers()
	_draw_viewport_frame()
	draw_rect(Rect2(Vector2.ZERO, _panel_size), BORDER_COLOR, false, 1.5)

## Threat Meter (design doc Phase 6.1) — see this class's own doc comment
## for the full reasoning. Iterates every generated cell same as the
## terrain pass above (cheap at this scale, same reasoning that pass
## already relies on) rather than trying to enumerate only "interesting"
## hexes — NoiseManager.get_noise_at() is already a plain Dictionary lookup.
func _draw_threat_markers() -> void:
	if not _noise_manager or not _hex_grid_map:
		return
	if not DisplaySettings.show_threat_meter_minimap:
		return
	for cell in _hex_grid_map.get_all_cells():
		var noise := _noise_manager.get_noise_at(cell.coord)
		if noise <= 0.0:
			continue
		if _fog_of_war_manager and not _fog_of_war_manager.is_at_least_explored(cell.coord):
			continue
		var pos := _world_to_minimap(HexCoord.axial_to_world(cell.coord))
		var radius := NoiseVisuals.radius(noise, THREAT_MARKER_RADIUS_MIN, THREAT_MARKER_RADIUS_MAX)
		var color := NoiseVisuals.color(noise)
		# A diamond, not a circle/square — shape-distinct from building dots
		# (circles) and hex tiles (flat squares), same accessibility
		# principle every other marker in this project already follows.
		draw_polygon(PackedVector2Array([
			pos + Vector2(0, -radius), pos + Vector2(radius, 0),
			pos + Vector2(0, radius), pos + Vector2(-radius, 0),
		]), PackedColorArray([color]))

## The main camera's current world-space view as a rectangle on the
## minimap — this is the whole point of showing a minimap specifically
## during Tactical zoom: it's the only time the player can't already see
## most of the map directly.
##
## Bug fix (found alongside CameraController's own zoom-direction fix,
## Phase 2.5.6): Camera2D's visible world width is screen_size / zoom.x, not
## screen_size * zoom.x (verified empirically — see CameraController's class
## doc comment) — the old multiply drew a viewport frame that shrank while
## actually zooming IN, the opposite of what it should do.
func _draw_viewport_frame() -> void:
	if not _camera or not _camera.is_inside_tree():
		return
	var screen_size := _camera.get_viewport().get_visible_rect().size
	var half_world_extent := screen_size / _camera.zoom / 2.0
	var world_center := _camera.get_screen_center_position()
	var top_left := _world_to_minimap(world_center - half_world_extent)
	var bottom_right := _world_to_minimap(world_center + half_world_extent)
	draw_rect(Rect2(top_left, bottom_right - top_left), VIEWPORT_FRAME_COLOR, false, 1.5)
