class_name WallMarkerRenderer
extends RefCounted

## Wall segment markers: a Line2D per WallSegment running from point_a to
## point_b (a piece's own real placement geometry, not hex-edge-locked) — a
## line, not a point icon, already shape-distinct from every other marker
## here. No fog-of-war gating — a wall is the player's own construction, same
## as a building.

var _layer: Node2D
var _wall_manager: WallManager
var _markers: Dictionary = {}  # int (WallSegment.id) -> Node2D (container: "Body" Line2D)

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

	return container

## Art, tiling mode, tint and geometry come from
## WallVisuals.apply_segment_look(), shared with the Tactical renderer and
## the placement preview. Only the width differs here: line_width() is the
## Strategic-zoom value, deliberately much thinner than the width the art is
## authored for, since at this zoom a wall is a marker rather than a
## structure the player is looking at.
func _apply_look(marker: Node2D, segment: WallSegment) -> void:
	var body := marker.get_node("Body") as Line2D
	WallVisuals.apply_segment_look(body, segment, WallVisuals.line_width(segment.tier, segment.is_breached()))
	var is_legacy := _wall_manager != null and _wall_manager.is_legacy_segment(segment)
	marker.modulate = WallVisuals.legacy_modulate() if is_legacy else WallVisuals.outer_modulate()

