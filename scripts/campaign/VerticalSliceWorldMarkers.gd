class_name VerticalSliceWorldMarkers
extends Node2D

## The slice's two marks on the map, drawn only while VerticalSliceDirector is
## running one:
##
## - The hex to clear, outlined, with how many dead are left on it and the count it
##   is cleared below — the grind made visible (EXP-1), so "clear the territory"
##   has a bar that moves while the squad fights.
## - The reported horde, while fog hides it: the scouts' dispatch said where it
##   was, and a dispatch the map does not show is one the player has to remember.
##   Once the horde is on a VISIBLE hex, ThreatOverlayView draws it instead.
##
## Screen-pixel sizes, same convention as ThreatOverlayView.

const TARGET_COLOR := Color(1.0, 0.85, 0.35)
const CLEARED_COLOR := Color(0.55, 0.95, 0.5)
const REPORT_COLOR := Color(0.95, 0.45, 0.35)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.8)

@export var director_path: NodePath
@export var infestation_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath

var _director: VerticalSliceDirector
var _infestation: InfestationManager
var _fog: FogOfWarManager
var _font: Font


func _ready() -> void:
	z_index = 49
	_font = ThemeDB.fallback_font
	if director_path:
		_director = get_node_or_null(director_path) as VerticalSliceDirector
	if infestation_manager_path:
		_infestation = get_node_or_null(infestation_manager_path) as InfestationManager
	if fog_of_war_manager_path:
		_fog = get_node_or_null(fog_of_war_manager_path) as FogOfWarManager



## Decided every frame rather than in _ready(): this node sits under WorldRoot, whose
## subtree readies before VerticalSliceDirector (a later Main.tscn sibling) has
## decided whether a slice is running.
func _process(_delta: float) -> void:
	visible = _director != null and _director.is_active()
	if visible:
		queue_redraw()


func _draw() -> void:
	if not _director or not _director.is_active() or not _infestation:
		return
	var pixel := 1.0 / maxf(0.0001, get_viewport().get_canvas_transform().get_scale().x)
	_draw_target(pixel)
	_draw_reported_horde(pixel)


func _draw_target(pixel: float) -> void:
	var coord := VerticalSliceConfig.TARGET_HEX
	var center := HexCoord.axial_to_world(coord)
	var corners := HexCoord.corner_points(center)
	var cleared := _infestation.is_cleared(coord)
	var color := CLEARED_COLOR if cleared else TARGET_COLOR
	var outline := corners.duplicate()
	outline.append(corners[0])
	draw_polyline(outline, Color(color, 0.9), 4.0 * pixel)
	var remaining := _infestation.zombie_count_at(coord)
	var seeded := maxi(1, _director.get_target_seeded())
	var threshold := _director.get_target_threshold()
	var progress := clampf(float(seeded - remaining) / float(maxi(1, seeded - threshold)), 0.0, 1.0)
	var title := "%s — CLEARED" % VerticalSliceConfig.TARGET_NAME.to_upper() if cleared else "CLEAR %s" % VerticalSliceConfig.TARGET_NAME.to_upper()
	_label(center + Vector2(0.0, -40.0 * pixel), title, color, 18, pixel)
	if not cleared:
		_label(center + Vector2(0.0, -18.0 * pixel), "%d dead left · cleared below %d" % [remaining, threshold], Color(1, 1, 1, 0.95), 14, pixel)
	var bar := Vector2(160.0, 10.0) * pixel
	var origin := center + Vector2(-bar.x * 0.5, -8.0 * pixel)
	draw_rect(Rect2(origin, bar), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(origin, Vector2(bar.x * progress, bar.y)), color)


func _draw_reported_horde(pixel: float) -> void:
	var horde := _director.get_horde()
	if horde == null or (_fog and _fog.is_visible(horde.hex_coord)):
		return
	var at := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	var radius := 18.0 * pixel
	for i in range(12):
		var a := TAU * float(i) / 12.0
		draw_arc(at, radius, a, a + TAU / 24.0, 3, Color(REPORT_COLOR, 0.9), 3.0 * pixel)
	_label(at + Vector2(0.0, -radius - 8.0 * pixel), "reported: ~%d" % horde.size, REPORT_COLOR, 15, pixel)


func _label(world: Vector2, text: String, color: Color, font_size: int, pixel: float) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_set_transform(world, 0.0, Vector2(pixel, pixel))
	draw_string(_font, Vector2(-width * 0.5 + 1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW_COLOR)
	draw_string(_font, Vector2(-width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
