class_name WallMarkerRenderer
extends RefCounted

## Wall segment markers: a Line2D per WallSegment running from point_a to
## point_b (a piece's own real placement geometry, not hex-edge-locked) — a
## line, not a point icon, already shape-distinct from every other marker
## here. No fog-of-war gating — a wall is the player's own construction, same
## as a building.

var _layer: Node2D
var _wall_manager: WallManager
var _markers: Dictionary = {}  # int (WallSegment.id) -> Node2D (container: "Body" Line2D + "DefenseWork" Polygon2D)

func _init(layer: Node2D, wall_manager: WallManager) -> void:
	_layer = layer
	_wall_manager = wall_manager

func seed(segments: Array[WallSegment]) -> void:
	for segment in segments:
		on_placed(segment)

func on_placed(segment: WallSegment) -> void:
	var marker := _build_marker(segment)
	_layer.add_child(marker)
	_markers[segment.id] = marker

## Shared by upgrade/breach/repair — all three change how the same segment
## should render (tier color/width, or the breached look) without moving it.
func on_state_changed(segment: WallSegment) -> void:
	var marker: Node2D = _markers.get(segment.id)
	if marker:
		_apply_look(marker, segment)

func on_removed(segment: WallSegment) -> void:
	var marker: Node2D = _markers.get(segment.id)
	if marker:
		marker.queue_free()
	_markers.erase(segment.id)

func on_defense_work_added(segment: WallSegment, _work_type: GameEnums.BuildingType) -> void:
	var marker: Node2D = _markers.get(segment.id)
	if marker:
		_update_defense_work(marker, segment)

## Territory shifting (a hex gaining/losing ZoC coverage) can flip a
## segment's outer/legacy classification without the segment itself changing
## (no placed/upgraded/breached/repaired signal fires) — call on
## LogisticsNetwork.network_recomputed.
func refresh_looks() -> void:
	if not _wall_manager:
		return
	for segment in _wall_manager.get_segments():
		on_state_changed(segment)

func _build_marker(segment: WallSegment) -> Node2D:
	var container := Node2D.new()

	var body := Line2D.new()
	body.name = "Body"
	container.add_child(body)
	_apply_look(container, segment)

	var defense_work := Polygon2D.new()
	defense_work.name = "DefenseWork"
	defense_work.visible = false
	container.add_child(defense_work)
	_update_defense_work(container, segment)

	return container

## LINE_TEXTURE_TILE + texture_repeat ENABLED for real tileable wall art
## (WallVisuals.tier_texture()) — Line2D natively tiles a texture along its
## own length. A breached segment keeps the flat alarm-red look regardless of
## art (texture cleared, not tiled red). default_color is still set with a
## texture assigned: Line2D multiplies texture color by default_color, so
## it's reset to white (no tint) whenever a real texture is in play, tier
## color only otherwise.
func _apply_look(marker: Node2D, segment: WallSegment) -> void:
	var body := marker.get_node("Body") as Line2D
	var breached := segment.is_breached()
	var texture := WallVisuals.tier_texture(segment.tier) if not breached else null
	body.texture = texture
	body.texture_mode = Line2D.LINE_TEXTURE_TILE
	body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	body.default_color = Color.WHITE if texture else (WallVisuals.breached_color() if breached else (WallVisuals.gate_color() if segment.is_gate else WallVisuals.tier_color(segment.tier)))
	WallVisuals.apply_line_geometry(body, segment.point_a, segment.point_b, WallVisuals.line_width(segment.tier, breached))
	var is_legacy := _wall_manager != null and _wall_manager.is_legacy_segment(segment)
	marker.modulate = WallVisuals.legacy_modulate() if is_legacy else WallVisuals.outer_modulate()

## Ditch/Oil Pit stack alongside a segment rather than replacing it — a small
## square at the segment's own midpoint, on top of the line.
func _update_defense_work(marker: Node2D, segment: WallSegment) -> void:
	var work := marker.get_node("DefenseWork") as Polygon2D
	if not segment.has_ditch and not segment.has_oil_pit:
		work.visible = false
		return
	work.visible = true
	var midpoint := (segment.point_a + segment.point_b) / 2.0
	var half := 5.0
	work.polygon = PackedVector2Array([
		midpoint + Vector2(-half, -half), midpoint + Vector2(half, -half),
		midpoint + Vector2(half, half), midpoint + Vector2(-half, half),
	])
	var texture := WallVisuals.defense_work_texture(segment.has_ditch, segment.has_oil_pit)
	work.texture = texture
	work.uv = TacticalHexView.quad_uv(texture)  ## Polygon2D.uv is texture-PIXEL-space, not normalized 0..1.
	work.color = Color.WHITE if texture else WallVisuals.defense_work_color(segment.has_ditch, segment.has_oil_pit)
