class_name HordeMarkerRenderer
extends RefCounted

## Spotted-horde markers. A horde gets a marker once its hex has actually
## been VISIBLE at least once ("spotted", not omniscient tracking), tracks
## live while VISIBLE, and freezes as a dimmed "last known position" ghost
## with a direction-of-travel line once vision is lost, rather than
## vanishing. Only hordes >= MIN_SIZE qualify — smaller hordes/lone zombies
## are Tactical-only (TacticalEntityLayer). Takes only FogOfWarManager as a
## dependency — callers pass the relevant Horde/coord/state directly, so this
## class never needs a HordeManager reference of its own.

signal spotted(horde: Horde)

const HORDE_MARKER_COLOR := Color(0.75, 0.15, 0.15)
const HORDE_GHOST_MODULATE := Color(1.0, 1.0, 1.0, 0.4)
const HORDE_DIRECTION_COLOR := Color(0.95, 0.85, 0.3, 0.9)
const HORDE_MARKER_RADIUS := 12.0
const HORDE_DIRECTION_LENGTH := 20.0
const MIN_SIZE: int = 100

var _layer: Node2D
var _fog_of_war_manager: FogOfWarManager
var _markers: Dictionary = {}            # int (Horde.id) -> Node2D (container: "Body" Polygon2D + "Direction" Line2D)
var _live: Dictionary = {}               # int (Horde.id) -> bool; true while live-tracking a VISIBLE hex
var _last_known_coord: Dictionary = {}   # int (Horde.id) -> Vector2i

func _init(layer: Node2D, fog_of_war_manager: FogOfWarManager) -> void:
	_layer = layer
	_fog_of_war_manager = fog_of_war_manager

func seed(hordes: Array[Horde]) -> void:
	for horde in hordes:
		on_spawned(horde)

func on_spawned(horde: Horde) -> void:
	if _qualifies(horde) and _is_visible(horde.hex_coord):
		_reveal_live(horde, horde.hex_coord)

func on_removed(horde: Horde) -> void:
	_remove_if_any(horde)

func on_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i) -> void:
	if not _qualifies(horde):
		_remove_if_any(horde)  # No-op if it never had one (e.g. always below threshold).
		return
	if _live.get(horde.id, false):
		if _is_visible(to_coord):
			_update_live_position(horde, to_coord)
		else:
			# Walked out of sight this step — freeze at the last hex it was
			# actually seen on (from_coord, still visible), with a direction
			# line pointing toward where it was headed.
			_freeze(horde, from_coord, to_coord)
	elif _is_visible(to_coord):
		_reveal_live(horde, to_coord)  # Newly spotted (or re-spotted) while moving.

## Covers a horde stationary (or off-screen) when the reason its visibility
## changes is something else moving — a building placed/removed, a supply
## line cut, night contraction — none of which fire horde_moved. Caller
## (StrategicOverlayManager) pre-filters hordes_at_coord from
## HordeManager.get_hordes_at(coord) off its own fog_state_changed handler.
func on_fog_state_changed(coord: Vector2i, state: GameEnums.FogState, hordes_at_coord: Array[Horde]) -> void:
	for horde in hordes_at_coord:
		if not _qualifies(horde):
			continue
		if state == GameEnums.FogState.VISIBLE:
			if not _live.get(horde.id, false):
				_reveal_live(horde, coord)
		elif _live.get(horde.id, false):
			_freeze(horde, coord, coord)  # Stationary loss of vision — no known heading, no direction line.

## Merge/split, or any other source of Horde.size changing outside a move
## (e.g. casualty accumulation), can cross MIN_SIZE in either direction
## without the horde moving or fog changing.
func on_size_changed(horde: Horde, _delta: int) -> void:
	if not _qualifies(horde):
		_remove_if_any(horde)
		return
	if not _markers.has(horde.id) and _is_visible(horde.hex_coord):
		_reveal_live(horde, horde.hex_coord)

func _qualifies(horde: Horde) -> bool:
	return horde.size >= MIN_SIZE

func _remove_if_any(horde: Horde) -> void:
	var marker: Node2D = _markers.get(horde.id)
	if marker:
		marker.queue_free()
	_markers.erase(horde.id)
	_live.erase(horde.id)
	_last_known_coord.erase(horde.id)

func _is_visible(coord: Vector2i) -> bool:
	return _fog_of_war_manager != null and _fog_of_war_manager.is_visible(coord)

## Creates the marker on first-ever spot, or un-dims/repositions an existing
## ghost on re-spot — either way ends live-tracking `horde` at `coord`.
func _reveal_live(horde: Horde, coord: Vector2i) -> void:
	var marker: Node2D = _markers.get(horde.id)
	if not marker:
		marker = _build_marker()
		_layer.add_child(marker)
		_markers[horde.id] = marker
	marker.position = HexCoord.axial_to_world(coord)
	marker.modulate = Color.WHITE
	(marker.get_node("Direction") as Line2D).visible = false
	_live[horde.id] = true
	_last_known_coord[horde.id] = coord
	spotted.emit(horde)

func _update_live_position(horde: Horde, coord: Vector2i) -> void:
	var marker: Node2D = _markers.get(horde.id)
	if marker:
		marker.position = HexCoord.axial_to_world(coord)
	_last_known_coord[horde.id] = coord

## Freezes `horde`'s marker at `at_coord` (its last actually-seen position),
## dims it, and — if `heading_toward_coord` differs — draws a short line
## toward wherever it was heading when last seen. Assumes the marker already
## exists (freezing only follows a prior reveal); no-op otherwise.
func _freeze(horde: Horde, at_coord: Vector2i, heading_toward_coord: Vector2i) -> void:
	var marker: Node2D = _markers.get(horde.id)
	if not marker:
		return
	marker.position = HexCoord.axial_to_world(at_coord)
	marker.modulate = HORDE_GHOST_MODULATE
	var direction := marker.get_node("Direction") as Line2D
	if at_coord != heading_toward_coord:
		var to_local := HexCoord.axial_to_world(heading_toward_coord) - HexCoord.axial_to_world(at_coord)
		direction.points = PackedVector2Array([Vector2.ZERO, to_local.normalized() * HORDE_DIRECTION_LENGTH])
		direction.visible = true
	else:
		direction.visible = false
	_live[horde.id] = false
	_last_known_coord[horde.id] = at_coord

func _build_marker() -> Node2D:
	var container := Node2D.new()

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = HORDE_MARKER_COLOR
	body.polygon = StrategicMarkerShapes.diamond_points(HORDE_MARKER_RADIUS)  # Diamond — distinct from buildings' triangle and units' circle.
	container.add_child(body)

	var direction := Line2D.new()
	direction.name = "Direction"
	direction.width = 3.0
	direction.default_color = HORDE_DIRECTION_COLOR
	direction.visible = false
	container.add_child(direction)

	return container
