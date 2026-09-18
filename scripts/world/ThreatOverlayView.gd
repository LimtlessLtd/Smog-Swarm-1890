class_name ThreatOverlayView
extends Node2D

## Draws the threat the simulation already knows about, at the scale the player
## plays at. PLAYER_EXPERIENCE.md's feedback criteria this answers: HORDE-1 (a big
## horde is seen, with its size), FB-2 (where), COMBAT-2 (who is fighting whom),
## DEF-1..3 (a siege looks like a siege) and the one the slice was built around —
## that the player can see what their own light and noise are doing.
##
## - **Attention footprint.** Every hex whose attraction clears
##   HordeManager.ATTRACTION_THRESHOLD, tinted by what dominates it (lamp light
##   or machine noise). "What you hear is what they hear" (§13), drawn.
## - **Hordes** on VISIBLE hexes: a mark sized by count, the count, and what the
##   horde is doing — wandering, drawn by a named building (with a line to it and
##   an ETA), or at the wall.
## - **Sieges**: the piece under attack, its HP, how many defenders reach it, and
##   at close zoom the band a bow reaches from (WallDefenseController).
## - **Pulses**: kills from cover and kills in the open float up where they happen;
##   a breach bursts.
##
## Sizes are in screen pixels (divided by the canvas scale), so a 100 m wall piece
## is findable at the hex-scale zoom where a 5 km hex fills the screen. Redrawn
## every frame: the number of hordes, sieges and pulses in view is small, and every
## one of them moves. Owns no state the game reads.

const HORDE_COLOR := Color(0.78, 0.12, 0.10)
const HORDE_RING_COLOR := Color(1.0, 0.82, 0.55)
const ATTRACTED_COLOR := Color(1.0, 0.72, 0.25)
const SIEGE_COLOR := Color(1.0, 0.25, 0.18)
const REACH_COLOR := Color(0.45, 0.85, 1.0)
const LIGHT_TINT := Color(1.0, 0.86, 0.35, 0.16)
const NOISE_TINT := Color(1.0, 0.45, 0.20, 0.16)
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.8)
## Hordes smaller than this are not marked: the ambient 1-3 strays would bury the
## map in dots. Same order as HordeMarkerRenderer.MIN_SIZE's strategic threshold,
## halved because this overlay also serves the local zoom where a 60-strong horde
## is worth seeing.
const MIN_HORDE_SIZE: int = 50
const PULSE_REAL_SECONDS: float = 1.4
const BURST_REAL_SECONDS: float = 2.0
## A pulse is emitted at most this often per horde or hex, summing the kills in
## between, so a volley of sixteen strikes reads as one "-32" and not sixteen "-2".
const PULSE_BATCH_REAL_SECONDS: float = 0.5
## Real seconds a siege forecast is reused before SiegeForecast.project() runs again
## (a few thousand steps each).
const FORECAST_REFRESH_REAL_SECONDS: float = 0.5

@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath
@export var noise_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var wall_defense_controller_path: NodePath
@export var combat_coordinator_path: NodePath

var _hordes: HordeManager
var _fog: FogOfWarManager
var _noise: NoiseManager
var _walls: WallManager
var _wall_defense: WallDefenseController
var _combat: CombatCoordinator
var _font: Font

var _pulses: Array[Dictionary] = []   # {world: Vector2, text: String, color: Color, born_ms: int}
var _bursts: Array[Dictionary] = []   # {world: Vector2, born_ms: int}
var _pending_kills: Dictionary = {}   # Vector2 world (rounded) -> {kills, cover, since_ms}
var _forecasts: Dictionary = {}       # Horde -> {text: String, danger: bool, at_ms: int}


func _ready() -> void:
	z_index = 50
	_font = ThemeDB.fallback_font
	if horde_manager_path:
		_hordes = get_node_or_null(horde_manager_path) as HordeManager
	if fog_of_war_manager_path:
		_fog = get_node_or_null(fog_of_war_manager_path) as FogOfWarManager
	if noise_manager_path:
		_noise = get_node_or_null(noise_manager_path) as NoiseManager
	if wall_manager_path:
		_walls = get_node_or_null(wall_manager_path) as WallManager
		_walls.wall_segment_breached.connect(_on_wall_breached)
	if wall_defense_controller_path:
		_wall_defense = get_node_or_null(wall_defense_controller_path) as WallDefenseController
	if combat_coordinator_path:
		_combat = get_node_or_null(combat_coordinator_path) as CombatCoordinator
		_combat.engagement_resolved.connect(_on_engagement_resolved)


func _process(_delta: float) -> void:
	_flush_pending_kills(false)
	queue_redraw()


func _draw() -> void:
	var pixel := _pixel()
	if _noise:
		_draw_attention(pixel)
	if _hordes:
		_draw_sieges(pixel)
		_draw_hordes(pixel)
	_draw_pulses(pixel)


# --- Attention footprint ------------------------------------------------------

func _draw_attention(pixel: float) -> void:
	for coord in _noise.get_attracting_hexes():
		if _noise.get_noise_at(coord) < HordeManager.ATTRACTION_THRESHOLD:
			continue
		var kind := _noise.get_dominant_kind_at(coord)
		var tint := LIGHT_TINT if kind == NoiseManager.KIND_LIGHT else NOISE_TINT
		var corners := HexCoord.corner_points(HexCoord.axial_to_world(coord))
		draw_colored_polygon(corners, tint)
		var outline := corners.duplicate()
		outline.append(corners[0])
		draw_polyline(outline, Color(tint.r, tint.g, tint.b, 0.55), 2.0 * pixel)


# --- Hordes -------------------------------------------------------------------

func _draw_hordes(pixel: float) -> void:
	for horde in _hordes.get_all_hordes():
		# A horde at the player's wall, or following the player's own light or
		# noise, is known whatever the fog says: it is coming for something the
		# player owns.
		if horde.size < MIN_HORDE_SIZE or not (_is_seen(horde.hex_coord) or horde.state == GameEnums.HordeState.ATTACKING or horde.attraction_source != null or _hordes.get_sieged_segment(horde) != null):
			continue
		var at := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
		if horde.resident_target_id == -1 and _hordes.get_sieged_segment(horde) == null:
			if pixel > 0.5:
				draw_circle(at, 3.0 * pixel, HORDE_RING_COLOR)
			if at.distance_to(get_global_mouse_position()) < 16.0 * pixel:
				_draw_label(at + Vector2(0, -16) * pixel, "%s residents" % _thousands(horde.size), TEXT_COLOR, 12, pixel)
			continue
		var radius := (9.0 + 4.0 * log(float(horde.size) / float(MIN_HORDE_SIZE)) / log(2.0)) * pixel
		var source: BuildingInstance = horde.attraction_source
		if source and horde.state != GameEnums.HordeState.ATTACKING:
			var to := HexCoord.axial_to_world(source.hex_coord) + source.local_position
			_draw_dashed(at, to, ATTRACTED_COLOR, 3.0 * pixel, 14.0 * pixel)
			var eta := _hordes.get_eta_seconds(horde)
			if eta > 0.0:
				_draw_label((at + to) * 0.5, "ETA %s" % _format_real(eta), ATTRACTED_COLOR, 14, pixel)
		# Keep the tactical sprites visible inside their threat marker.
		if pixel > 2.0:
			draw_circle(at, radius, Color(HORDE_COLOR, 0.65))
		draw_arc(at, radius, 0.0, TAU, 32, HORDE_RING_COLOR, 2.0 * pixel)
		# Beside the mark, not above it: a sieging horde stands on its wall piece,
		# whose readout is drawn above.
		_draw_label(at + Vector2(radius + 8.0 * pixel, 6.0 * pixel), _thousands(horde.size), TEXT_COLOR, 18, pixel, false)
		_draw_label(at + Vector2(0.0, radius + 16.0 * pixel), _doing(horde), ATTRACTED_COLOR if source else Color(TEXT_COLOR, 0.8), 13, pixel)


func _doing(horde: Horde) -> String:
	if horde.has_combat_target:
		return "closing on troops"
	if horde.state == GameEnums.HordeState.ATTACKING:
		return "at the wall"
	var source: BuildingInstance = horde.attraction_source
	if source:
		var sense := "light" if _noise and _noise.get_dominant_kind_at(horde.hex_coord) == NoiseManager.KIND_LIGHT else "noise"
		return "drawn by the %s of your %s" % [sense, source.definition.display_name]
	return "wandering"


# --- Sieges -------------------------------------------------------------------

func _draw_sieges(pixel: float) -> void:
	var pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 160.0)
	var sieging := _hordes.get_sieging_hordes()
	for horde in _forecasts.keys():
		if not sieging.has(horde):
			_forecasts.erase(horde)
	for horde in sieging:
		var segment := _hordes.get_sieged_segment(horde)
		if segment == null:
			continue
		var mid := (segment.point_a + segment.point_b) * 0.5
		var reach := WallDefenseController.RANGED_REACH_METRES * HexCoord.WORLD_UNITS_PER_REAL_METER
		if reach / pixel > 24.0:
			draw_circle(mid, reach, Color(REACH_COLOR, 0.07))
			draw_arc(mid, reach, 0.0, TAU, 48, Color(REACH_COLOR, 0.6), 2.0 * pixel)
			_draw_label(mid + Vector2(0.0, reach + 14.0 * pixel), "bows strike from inside this ring", REACH_COLOR, 12, pixel)
		draw_line(segment.point_a, segment.point_b, Color(SIEGE_COLOR, pulse), maxf(6.0 * pixel, segment.point_a.distance_to(segment.point_b) * 0.08))
		draw_arc(mid, 22.0 * pixel, 0.0, TAU, 24, Color(SIEGE_COLOR, pulse), 3.0 * pixel)
		var hp_ratio := clampf(segment.current_hp / maxf(0.001, segment.get_max_hp()), 0.0, 1.0)
		var bar := Vector2(90.0, 9.0) * pixel
		var bar_origin := mid + Vector2(-bar.x * 0.5, -78.0 * pixel)
		draw_rect(Rect2(bar_origin, bar), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(bar_origin, Vector2(bar.x * hp_ratio, bar.y)), SIEGE_COLOR.lerp(Color(0.4, 0.9, 0.35), hp_ratio))
		var defenders: Array[UnitInstance] = _wall_defense.get_defenders(horde, segment) if _wall_defense else []
		_draw_label(mid + Vector2(0.0, -86.0 * pixel), "%s %d%%  ·  %d defender%s in reach" % ["GATE" if segment.is_gate else "WALL", int(round(hp_ratio * 100.0)), defenders.size(), "" if defenders.size() == 1 else "s"], TEXT_COLOR if not defenders.is_empty() else SIEGE_COLOR, 14, pixel)
		var forecast := _forecast(horde, segment, defenders)
		_draw_label(mid + Vector2(0.0, -104.0 * pixel), forecast["text"], SIEGE_COLOR if forecast["danger"] else Color(0.55, 0.95, 0.5), 14, pixel)


## "At this rate": what SiegeForecast projects if nothing about the defence
## changes. The line that tells the player whether the defenders they have in reach
## are enough, before the wall answers it.
func _forecast(horde: Horde, segment: WallSegment, defenders: Array[UnitInstance]) -> Dictionary:
	var now := Time.get_ticks_msec()
	var cached: Dictionary = _forecasts.get(horde, {})
	if not cached.is_empty() and now - int(cached["at_ms"]) < int(FORECAST_REFRESH_REAL_SECONDS * 1000.0):
		return cached
	var kills := 0
	for instance in defenders:
		kills += SiegeForecast.kills_per_strike(instance.definition, TimeCycleManager.is_day())
	var per_defender := int(round(float(kills) / float(defenders.size()))) if not defenders.is_empty() else 0
	var projection := SiegeForecast.project(horde.size, segment.current_hp, defenders.size(), per_defender, TimeCycleManager.is_night())
	var text := "at this rate: the wall holds"
	var danger := false
	if projection["outcome"] == &"breach":
		text = "at this rate: wall falls in %s with %s still standing" % [_format_real(projection["seconds"]), _thousands(projection["horde_left"])]
		danger = true
	elif projection["outcome"] == &"destroyed":
		text = "at this rate: horde destroyed in %s" % _format_real(projection["seconds"])
	cached = {"text": text, "danger": danger, "at_ms": now}
	_forecasts[horde] = cached
	return cached


# --- Pulses -------------------------------------------------------------------

func _on_engagement_resolved(_instance: UnitInstance, horde: Horde, result: Dictionary) -> void:
	var killed := int(result.get("zombies_killed", 0))
	if killed <= 0:
		return
	var at := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	var key := Vector2i(int(at.x), int(at.y))
	var entry: Dictionary = _pending_kills.get(key, {"world": at, "kills": 0, "cover": false, "since_ms": Time.get_ticks_msec()})
	entry["kills"] = int(entry["kills"]) + killed
	entry["cover"] = bool(entry["cover"]) or result.get("from_cover", false)
	_pending_kills[key] = entry


func _flush_pending_kills(force: bool) -> void:
	var now := Time.get_ticks_msec()
	for key in _pending_kills.keys():
		var entry: Dictionary = _pending_kills[key]
		if not force and now - int(entry["since_ms"]) < int(PULSE_BATCH_REAL_SECONDS * 1000.0):
			continue
		_pulses.append({"world": entry["world"], "text": "-%d" % int(entry["kills"]), "color": REACH_COLOR if entry["cover"] else HORDE_RING_COLOR, "born_ms": now})
		_pending_kills.erase(key)


func _on_wall_breached(segment: WallSegment) -> void:
	_bursts.append({"world": (segment.point_a + segment.point_b) * 0.5, "born_ms": Time.get_ticks_msec()})


func _draw_pulses(pixel: float) -> void:
	var now := Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	for pulse in _pulses:
		var age := float(now - int(pulse["born_ms"])) / 1000.0
		if age > PULSE_REAL_SECONDS:
			continue
		kept.append(pulse)
		var fade := 1.0 - age / PULSE_REAL_SECONDS
		var color: Color = pulse["color"]
		_draw_label(pulse["world"] + Vector2(-60.0, -20.0 - 40.0 * age) * pixel, pulse["text"], Color(color, fade), 18, pixel)
	_pulses = kept
	var kept_bursts: Array[Dictionary] = []
	for burst in _bursts:
		var age := float(now - int(burst["born_ms"])) / 1000.0
		if age > BURST_REAL_SECONDS:
			continue
		kept_bursts.append(burst)
		var t := age / BURST_REAL_SECONDS
		draw_arc(burst["world"], (20.0 + 120.0 * t) * pixel, 0.0, TAU, 40, Color(SIEGE_COLOR, 1.0 - t), 5.0 * pixel)
		_draw_label(burst["world"] + Vector2(0.0, -30.0 * pixel), "BREACH", Color(SIEGE_COLOR, 1.0 - t * 0.5), 22, pixel)
	_bursts = kept_bursts


# --- Helpers ------------------------------------------------------------------

func _is_seen(coord: Vector2i) -> bool:
	return _fog == null or _fog.is_visible(coord)


func _pixel() -> float:
	return 1.0 / maxf(0.0001, get_viewport().get_canvas_transform().get_scale().x)


func _draw_label(world: Vector2, text: String, color: Color, font_size: int, pixel: float, centred: bool = true) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_set_transform(world, 0.0, Vector2(pixel, pixel))
	var origin := Vector2(-width * 0.5 if centred else 0.0, 0.0)
	draw_string(_font, origin + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW_COLOR)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.001:
		return
	var direction := (to - from) / length
	var travelled := 0.0
	while travelled < length:
		var end := minf(travelled + dash, length)
		draw_line(from + direction * travelled, from + direction * end, color, width)
		travelled += dash * 2.0


static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out


static func _format_real(game_seconds: float) -> String:
	var real := int(round(game_seconds / TickManager.SPEED_MULTIPLIERS[1]))
	return "%d:%02d" % [real / 60, real % 60]
