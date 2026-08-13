class_name AttackAlertRenderer
extends RefCounted

## Pulsing ring at a hex under attack, fed by EventManager's COMBAT category
## (wall breach, unit engaged, building ruined — every one of those carries a
## real hex_coord). Fixed-duration pulse, re-triggered (timer restarted, not
## stacked) by a further COMBAT event at the same hex while still showing.

const ALERT_COLOR := Color(0.95, 0.75, 0.1, 0.9)  ## Amber ring — distinct from buildings' triangle, units' filled circle, hordes' filled diamond.
const ALERT_RADIUS := 22.0
const ALERT_SECONDS: float = 8.0

var _layer: Node2D
var _timer_host: Node  ## Owns the Timer nodes — RefCounted can't add_child(); StrategicOverlayManager itself.
var _markers: Dictionary = {}  # Vector2i -> {"node": Node2D, "timer": Timer}

func _init(layer: Node2D, timer_host: Node) -> void:
	_layer = layer
	_timer_host = timer_host

func on_event_raised(event: GameEvent) -> void:
	if event.category == GameEnums.EventCategory.COMBAT:
		_pulse(event.hex_coord)

func _pulse(coord: Vector2i) -> void:
	var existing: Dictionary = _markers.get(coord, {})
	if not existing.is_empty():
		(existing["timer"] as Timer).start()
		return
	var ring := _build_ring()
	ring.position = HexCoord.axial_to_world(coord)
	_layer.add_child(ring)
	_start_pulse(ring)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = ALERT_SECONDS
	_timer_host.add_child(timer)
	timer.timeout.connect(_on_timeout.bind(coord))
	timer.start()

	_markers[coord] = {"node": ring, "timer": timer}

func _on_timeout(coord: Vector2i) -> void:
	var entry: Dictionary = _markers.get(coord, {})
	if not entry.is_empty():
		(entry["node"] as Node2D).queue_free()
		(entry["timer"] as Timer).queue_free()
	_markers.erase(coord)

func _build_ring() -> Line2D:
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = ALERT_COLOR
	ring.closed = true
	ring.points = StrategicMarkerShapes.circle_points(ALERT_RADIUS, 16)
	return ring

## `ring` must already be inside the tree (create_tween() requires it) —
## called right after add_child() above, never before.
func _start_pulse(ring: Line2D) -> void:
	var tween := ring.create_tween()
	tween.set_loops()
	tween.tween_property(ring, "modulate:a", 0.25, 0.5)
	tween.tween_property(ring, "modulate:a", 1.0, 0.5)
