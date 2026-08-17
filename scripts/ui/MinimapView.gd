class_name MinimapView
extends Control

## Always-visible minimap of the Strategic layer while zoomed into
## Tactical view. Shown only while CameraController.is_tactical_zoom() is
## true, not in both view modes — Strategic view already IS the full map,
## so a minimap of it there would be redundant chrome rather than
## restoring lost awareness (the hard-cut zoom otherwise leaves the player
## with zero awareness of anything happening elsewhere on the map while
## zoomed into one hex cluster). Same "show/hide off tactical_mode_changed"
## wiring StrategicOverlayManager uses, just inverted (that one hides
## during Tactical, this one shows only during Tactical).
##
## Code-drawn placeholder (a single _draw() call), same convention as
## every other visual in this project — reuses TerrainVisuals/FogVisuals/
## BuildingVisuals directly rather than a fourth copy of any of their
## color logic, so this agrees with the Strategic/Tactical views it's a
## miniature of. Non-uniform stretch (world bounds mapped independently on
## X/Y into a fixed-size panel, no aspect-ratio letterboxing) — a
## simplification appropriate to placeholder fidelity, not real cartography.
##
## Performance: terrain+building content only redraws off
## FogOfWarManager.fog_state_changed / BuildingManager.building_placed/
## _removed (rare events), matching LogisticsNetwork/FogOfWarManager's own
## "recompute on the signal, not every frame" precedent. The one thing
## that DOES need to track continuously, the camera-viewport frame,
## redraws off a modest fixed-interval Timer instead of every frame —
## smooth enough to feel live while panning, far cheaper than full framerate.
##
## Zoom: mouse wheel over the minimap panel adjusts `_zoom_level`
## independently of the main camera's own zoom — "the mini map... should be
## able to be zoomed in and out independently of where the camera is, at the
## moment its so zoomed out its unusable" (user feedback; the minimap always
## fit the ENTIRE map into one small fixed-size panel before this, which
## reduced every hex to ~3px regardless of camera state). At `_zoom_level`
## 1.0 (default) the full world still fits, same as before. Above 1.0, only a
## `_world_bounds_size / _zoom_level` window is shown, centered on the main
## camera's current world position (clamped to stay inside the full map) —
## the window recenters as the camera pans/refreshes (same VIEWPORT_REFRESH_SECONDS
## timer already redraws off), so zooming in doesn't strand the view on a
## fixed point while play continues elsewhere.
##
## Spotted-horde markers are NOT drawn here — that marker system is
## Strategic-only (StrategicOverlayManager's own HordeMarkerRenderer). This
## draws what StrategicOverlayManager already draws (buildings) plus
## terrain, not a superset invented just for the minimap.
##
## Threat Meter: a translucent diamond marker (shape-distinct from the
## plain square hex dots and circular building dots already drawn here) at
## every hex NoiseManager.get_noise_at() reports as nonzero, sized AND
## colored by intensity (amber, low, small -> red, high, large) via one
## shared lerp — two independent visual cues for the same value, not just
## a color ramp. Same fog gate as building icons (at-least-EXPLORED, not
## full VISIBLE) — a noise source is the player's own industry,
## already-known territory works the same way a building icon does here.

const VIEWPORT_REFRESH_SECONDS: float = 0.1

const MIN_ZOOM: float = 1.0    ## Whole map fits the panel — the pre-zoom behavior.
## 40, not 8 — "Mini map zoom is still too far away" (user feedback): the
## real map is 154x179 hexes (HexCoord.gd's own doc comment), so even at 8x
## the zoomed window was still ~25 hexes wide across this panel's 200px, not
## meaningfully more useful than the unzoomed view. At 40x the window is
## ~5 hexes wide — small enough to actually read individual hex/building
## dots up close.
const MAX_ZOOM: float = 40.0
const ZOOM_STEP_FACTOR: float = 1.35  ## Multiplicative per wheel notch — feels smoother than a flat additive step across this range.

const COASTLINE_COLOR: Color = Color(0.75, 0.72, 0.62, 0.85)  ## Matches CoastlineOutlineView.OUTLINE_COLOR — same shape, same look, at minimap scale.
const BUILDING_DOT_RADIUS: float = 2.5
const BACKGROUND_COLOR: Color = Color("#1f150f")
const BORDER_COLOR: Color = Color("#cfa24e")
const VIEWPORT_FRAME_COLOR: Color = Color("#f4e7c5")

## Threat Meter marker radius bounds — minimap-space pixels, not world
## units (see NoiseVisuals.gd for the shared color/intensity curve this
## scales against, also used by StrategicOverlayManager's own world-view copy).
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
var _coastline_segments: PackedVector2Array = PackedVector2Array()  ## World-space, from HexCoord.coastline_segments() — same shape CoastlineOutlineView draws on the main map, computed once at setup().

var _zoom_level: float = MIN_ZOOM
## Set fresh at the top of every _draw() call (see _effective_bounds()) —
## _world_to_minimap() reads these rather than the raw _world_bounds_*
## fields so every draw call within one frame maps against the same window.
var _effective_bounds_min: Vector2 = Vector2.ZERO
var _effective_bounds_size: Vector2 = Vector2.ONE

## `panel_size` is passed in explicitly rather than read back from this
## Control's own `size` — MainHUD's own layout-helper doc comment already
## flags Control.size/get_combined_minimum_size() as able to read stale on
## the same frame a Control is first positioned; an explicit fixed size
## sidesteps that class of bug entirely. `noise_manager` is optional —
## unset just means no Threat Meter markers, everything else here is unaffected.
func setup(hex_grid_map: HexGridMap, building_manager: BuildingManager, fog_of_war_manager: FogOfWarManager, camera: CameraController, panel_size: Vector2, noise_manager: NoiseManager = null) -> void:
	_hex_grid_map = hex_grid_map
	_building_manager = building_manager
	_fog_of_war_manager = fog_of_war_manager
	_camera = camera
	_panel_size = panel_size
	_noise_manager = noise_manager

	# A Control's _draw() calls are NOT clipped to its own rect by default —
	# every draw call here already stayed inside 0.._panel_size at
	# MIN_ZOOM (whole map exactly fills the panel), but zooming in shrinks
	# the effective world-space window (_refresh_effective_bounds()) and any
	# content OUTSIDE that window — the coastline especially, drawn
	# unconditionally at full world extent regardless of zoom — maps to
	# normalized coordinates outside [0,1] and bled past the panel's own
	# border into the rest of the HUD (a real user screenshot caught this:
	# the coastline spilling out above the minimap once zoomed in).
	clip_contents = true

	_compute_world_bounds()
	_coastline_segments = HexCoord.coastline_segments(_hex_grid_map) if _hex_grid_map else PackedVector2Array()

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

## DisplaySettings.show_threat_meter_minimap is the only flag this class
## itself consults (terrain/buildings/viewport frame aren't "overlays" in
## the sense being toggled here, they're the minimap's own baseline
## content). A blanket redraw on ANY flag changing is simplest and cheap
## enough at this scale — same "just redraw, don't bother diffing which
## flag changed" reasoning fog_state_changed/building_changed lean on.
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

## Mouse wheel over the panel — zooms the minimap itself, never the main
## camera (Control.gui_input only fires for events actually over this
## Control's own rect, so this can't be confused with camera zoom input
## elsewhere on screen).
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_level = clampf(_zoom_level * ZOOM_STEP_FACTOR, MIN_ZOOM, MAX_ZOOM)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_level = clampf(_zoom_level / ZOOM_STEP_FACTOR, MIN_ZOOM, MAX_ZOOM)
	else:
		return
	accept_event()
	queue_redraw()

## Recomputes the world-space window this draw call maps against — the full
## map at _zoom_level 1.0, or a `_world_bounds_size / _zoom_level` window
## centered on the main camera's current position (clamped inside the full
## map) above that. Called once per _draw(), not per _world_to_minimap()
## call, so every dot/marker in the same frame maps against one consistent window.
func _refresh_effective_bounds() -> void:
	if _zoom_level <= MIN_ZOOM or not _camera or not _camera.is_inside_tree():
		_effective_bounds_min = _world_bounds_min
		_effective_bounds_size = _world_bounds_size
		return
	var window_size := _world_bounds_size / _zoom_level
	var center := _camera.get_screen_center_position()
	var window_min := center - window_size / 2.0
	window_min.x = clampf(window_min.x, _world_bounds_min.x, _world_bounds_min.x + _world_bounds_size.x - window_size.x)
	window_min.y = clampf(window_min.y, _world_bounds_min.y, _world_bounds_min.y + _world_bounds_size.y - window_size.y)
	_effective_bounds_min = window_min
	_effective_bounds_size = window_size

func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var normalized := (world_pos - _effective_bounds_min) / _effective_bounds_size
	return normalized * _panel_size

## A hex's real six corners (HexCoord.corner_points() — the exact shape
## HexCellView/TacticalHexView/CoastlineOutlineView all already draw),
## mapped through _world_to_minimap() one corner at a time. Replaces an
## earlier flat-square approximation that had TWO separate bugs, both from
## treating this as a square-packing problem instead of just drawing the
## real hex: (1) a user screenshot showed plain squares, not hexes, because
## draw_rect() was never going to look hex-shaped no matter how it was
## sized; (2) the square half-size was computed from HexCoord.HEX_SIZE
## (512, the hex's own CIRCUMRADIUS) when the value that actually matters
## for tiles to touch is the CENTER-TO-CENTER spacing between neighboring
## hexes — HexCoord.axial_to_world()'s own formula puts that at
## sqrt(3)*HEX_SIZE (~887), not HEX_SIZE itself, so the old squares were
## undersized by a factor of sqrt(3) (~1.73x) and always left a gap
## regardless of zoom. Drawing the real polygon sidesteps both: adjacent
## hexes share an edge by construction (same corner-point geometry the main
## map itself uses, not a size someone has to get right), so there's no
## spacing constant to derive or get wrong.
func _hex_polygon_minimap(coord: Vector2i) -> PackedVector2Array:
	var corners := HexCoord.corner_points(HexCoord.axial_to_world(coord))
	var mapped := PackedVector2Array()
	for corner in corners:
		mapped.append(_world_to_minimap(corner))
	return mapped

func _draw() -> void:
	_refresh_effective_bounds()
	draw_rect(Rect2(Vector2.ZERO, _panel_size), BACKGROUND_COLOR)
	if not _hex_grid_map:
		return

	_draw_coastline()

	if _fog_of_war_manager:
		for cell in _hex_grid_map.get_all_cells():
			var fog_state := _fog_of_war_manager.get_fog_state(cell.coord)
			if fog_state == GameEnums.FogState.UNSEEN:
				continue  ## Never scouted — the minimap shouldn't leak information the main view wouldn't either.
			var color := TerrainVisuals.biome_color(cell.biome_type, cell.soil_fertility) * FogVisuals.tint_color(fog_state)
			draw_colored_polygon(_hex_polygon_minimap(cell.coord), color)

	if _building_manager:
		for instance in _building_manager.get_all_buildings():
			if _fog_of_war_manager and not _fog_of_war_manager.is_at_least_explored(instance.hex_coord):
				continue
			var pos := _world_to_minimap(HexCoord.axial_to_world(instance.hex_coord))
			draw_circle(pos, BUILDING_DOT_RADIUS, BuildingVisuals.category_color(instance.definition.category))

	_draw_threat_markers()
	_draw_viewport_frame()
	draw_rect(Rect2(Vector2.ZERO, _panel_size), BORDER_COLOR, false, 1.5)

## Unconditional — NOT gated by FogOfWarManager, unlike every other layer
## this view draws. "We should be able to see an outline of the British
## Isles on the minimap so users know where they are looking abouts" (user
## request) — a landmass's own outline shape is public knowledge, the same
## reasoning CoastlineOutlineView's own doc comment already established for
## the main map view; this draws the identical HexCoord.coastline_segments()
## shape at minimap scale so the player always has an orientation reference,
## even on a mostly-UNSEEN map.
func _draw_coastline() -> void:
	for i in range(0, _coastline_segments.size(), 2):
		draw_line(_world_to_minimap(_coastline_segments[i]), _world_to_minimap(_coastline_segments[i + 1]), COASTLINE_COLOR, 1.0)

## Iterates every generated cell same as the terrain pass above (cheap at
## this scale) rather than trying to enumerate only "interesting" hexes —
## NoiseManager.get_noise_at() is already a plain Dictionary lookup.
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
		# A diamond, not a circle/square — shape-distinct from building
		# dots (circles) and hex tiles (flat squares).
		draw_polygon(PackedVector2Array([
			pos + Vector2(0, -radius), pos + Vector2(radius, 0),
			pos + Vector2(0, radius), pos + Vector2(-radius, 0),
		]), PackedColorArray([color]))

## The main camera's current world-space view as a rectangle on the
## minimap — this is the whole point of showing a minimap specifically
## during Tactical zoom: it's the only time the player can't already see
## most of the map directly. Camera2D's visible world width is screen_size
## / zoom.x, not screen_size * zoom.x (see CameraController's own class
## doc comment on the zoom-direction fix).
func _draw_viewport_frame() -> void:
	if not _camera or not _camera.is_inside_tree():
		return
	var screen_size := _camera.get_viewport().get_visible_rect().size
	var half_world_extent := screen_size / _camera.zoom / 2.0
	var world_center := _camera.get_screen_center_position()
	var top_left := _world_to_minimap(world_center - half_world_extent)
	var bottom_right := _world_to_minimap(world_center + half_world_extent)
	draw_rect(Rect2(top_left, bottom_right - top_left), VIEWPORT_FRAME_COLOR, false, 1.5)
