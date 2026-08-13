class_name StrategicMarkerShapes
extends RefCounted

## Shared polygon-point helpers for StrategicOverlayManager's renderer
## collaborators (scripts/world/overlay/).

static func circle_points(radius: float, segments: int = 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

static func diamond_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
