class_name ThreatMarkerRenderer
extends RefCounted

## Threat Meter, Strategic world-view surface (MinimapView has its own copy)
## — a translucent diamond per noisy hex, sized/colored by intensity via the
## shared NoiseVisuals lookup both surfaces read from. Rebuilt from scratch
## on refresh(). Gated on at-least-EXPLORED fog state, same as building
## icons — a noise source is the player's own industry, already-known
## territory.

const RADIUS_MIN := 8.0
const RADIUS_MAX := 26.0

var _layer: Node2D
var _hex_grid_map: HexGridMap
var _noise_manager: NoiseManager
var _fog_of_war_manager: FogOfWarManager
var _markers: Dictionary = {}  # Vector2i -> Node2D

func _init(layer: Node2D, hex_grid_map: HexGridMap, noise_manager: NoiseManager, fog_of_war_manager: FogOfWarManager) -> void:
	_layer = layer
	_hex_grid_map = hex_grid_map
	_noise_manager = noise_manager
	_fog_of_war_manager = fog_of_war_manager

func refresh() -> void:
	if not _hex_grid_map or not _noise_manager:
		return
	var wanted: Dictionary = {}  # Vector2i -> float (noise level)
	for cell: HexCell in _hex_grid_map.get_all_cells():
		var noise := _noise_manager.get_noise_at(cell.coord)
		if noise > 0.0 and (not _fog_of_war_manager or _fog_of_war_manager.is_at_least_explored(cell.coord)):
			wanted[cell.coord] = noise

	for coord in _markers.keys():
		if not wanted.has(coord):
			_markers[coord].queue_free()
			_markers.erase(coord)
	for coord in wanted:
		var noise: float = wanted[coord]
		if _markers.has(coord):
			_apply_look(_markers[coord], noise)
		else:
			var marker := _build_marker(coord, noise)
			_layer.add_child(marker)
			_markers[coord] = marker

func _build_marker(coord: Vector2i, noise: float) -> Node2D:
	var marker := Polygon2D.new()
	marker.position = HexCoord.axial_to_world(coord)
	_apply_look(marker, noise)
	return marker

func _apply_look(marker: Polygon2D, noise: float) -> void:
	var r := NoiseVisuals.radius(noise, RADIUS_MIN, RADIUS_MAX)
	marker.color = NoiseVisuals.color(noise)
	marker.polygon = StrategicMarkerShapes.diamond_points(r)  # Same shape MinimapView's own copy uses.
