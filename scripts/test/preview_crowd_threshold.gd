extends Node2D

## Renders the candidate `high_fidelity_threshold` values (D82) so the choice is
## made by looking rather than by arithmetic. One PNG per candidate zoom.
##
## Run (NOT --headless — a headless viewport has no texture to read, the same
## constraint smoke_screenshot.gd and capture_project_review_shots.gd record):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/preview_crowd_threshold.tscn
##
## Deliberately NOT the real Main.tscn, and the difference matters both ways.
##
## What this buys: the multi-minute HexMapGenerator boot is skipped, so a
## threshold can be re-picked and re-photographed in seconds — the same reason
## preview_relief_ingame.gd exists beside capture_project_review_shots.gd.
##
## What this costs, stated plainly so these images are not over-read: when these
## were shot the scene drew the PROPOSED state, not the built one — tight-cropped
## sprites, D76's metric figure scale and D79's clustered resident density were
## all decisions with no code behind them. Two of the three landed the same day
## (the crop and metric scale); **D79's urban clustering did not**, so the
## resident densities here are still ahead of the game, and a real battle-scale
## frame is thinner than these images until D78/D79 land. `06_battle_scale.png`
## from smoke_screenshot.gd is the photograph of what ships.
##
## Ground is flat and untextured on purpose. The question is whether a figure
## reads at N px, and putting the real terrain mesh underneath would make that a
## judgement about terrain contrast instead.

const OUT_DIR := "user://threshold_shots"
const WINDOW_SIZE := Vector2i(1280, 720)

## Frames waited before each capture. Far smaller than the screenshot scripts'
## 200 because there is nothing streamed here — no relief tiles, no mesh chunks,
## no hydration. Only the MultiMesh upload has to land.
const WARMUP_FRAMES: int = 8

## The candidates D82 brackets. 2.0 was the threshold when these were shot,
## included so the images carry their own before/after rather than needing one
## described; D85 moved it to 48.0 on the strength of the ENGULF_ZOOMS sweep.
const ZOOMS: Array[float] = [2.0, 12.0, 16.0, 20.0, 24.0, 32.0]

## Candidates past 32, shot with the horde ENGULFING the viewport rather than
## sitting in it. That is the framing the crowd-size requirement rides on — "at
## least as many as They Are Billions holds at once" is a statement about the
## worst case, and the worst case is a horde arriving, not a city standing
## still. Going deeper trades crowd for legibility on a 1/zoom^2 curve, so this
## sweep exists to find where that trade stops being worth it.
const ENGULF_ZOOMS: Array[float] = [32.0, 40.0, 48.0, 64.0]

## D76: a 1.8 m human drawn at the RTS convention of ~2x life so it reads at all.
const FIGURE_METRES: float = 3.5

## D79's densest clustered case — a London hex at order 5e5 over ~60% of its
## 64.7 km^2 — and a horde, which packs ~19x tighter because a mob is a mob.
const RESIDENT_DENSITY_PER_M2: float = 0.0129
const HORDE_DENSITY_PER_M2: float = 0.25

## Fraction of the viewport the horde disc covers. A horde is normally larger
## than the screen at these zooms (D80's recalibrated spread), so this is a
## deliberate under-statement: showing its EDGE is more informative than filling
## the frame with it, because the edge is where a player reads "how many".
const HORDE_VIEW_FRACTION: float = 0.22

## 1.35 rather than 1.0: a disc of exactly the viewport's area still leaves the
## corners bare, because the viewport is a rectangle and the disc is not.
const ENGULF_VIEW_FRACTION: float = 1.35

const SQUAD_SIZE: int = 12

const GROUND_COLOR := Color(0.42, 0.40, 0.31)   ## Mid olive-tan, sampled from the game's own tactical framing.
const HORDE_CENTRE_FRACTION := Vector2(0.30, 0.34)

const FRAME_PX: int = 128  ## Source resolution for the cropped sprite. See bench_zombie_render.gd for why not 2048.

var _camera: Camera2D
var _ground: Polygon2D
var _residents: MultiMeshInstance2D
var _horde: MultiMeshInstance2D
var _squad: Node2D
var _caption: Label
var _subcaption: Label

var _zombie_texture: Texture2D
var _unit_texture: Texture2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = WINDOW_SIZE
	_rng.seed = 20260907

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_zombie_texture = _cropped("res://assets/zombies/zombie_0_s.png", Color(0.33, 0.4, 0.27))
	_unit_texture = _cropped("res://assets/units/redcoat_s.png", Color(0.85, 0.8, 0.7))

	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()

	_ground = Polygon2D.new()
	_ground.color = GROUND_COLOR
	_ground.z_index = -10
	add_child(_ground)

	_residents = _make_layer(_zombie_texture, 0)
	_horde = _make_layer(_zombie_texture, 1)
	_squad = Node2D.new()
	_squad.z_index = 2
	add_child(_squad)

	var overlay := CanvasLayer.new()
	add_child(overlay)
	_caption = _make_label(overlay, 16, Vector2(20, 14), 30)
	_subcaption = _make_label(overlay, 20, Vector2(20, 48), 22)

	await _capture_all()
	get_tree().quit(0)


func _make_layer(texture: Texture2D, z: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.mesh = QuadMesh.new()
	mm.instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = texture
	mmi.z_index = z
	add_child(mmi)
	return mmi


func _make_label(parent: CanvasLayer, size: int, pos: Vector2, _line: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


## Tight-crops to the sprite's own non-transparent pixels, which is the fix the
## backlog's crop item describes and TextureCropUtil already implements for UI.
## Done here rather than through that class because this scene needs an Image to
## downscale, not an AtlasTexture view. Without it the figure renders at ~40% of
## the size the metric scale asks for and floats above its own feet — see the
## measured alpha bounding boxes in the crop item.
func _cropped(path: String, fallback: Color) -> Texture2D:
	if not ResourceLoader.exists(path):
		var blob := Image.create(FRAME_PX, FRAME_PX, false, Image.FORMAT_RGBA8)
		blob.fill(Color(fallback.r, fallback.g, fallback.b, 0.0))
		blob.fill_rect(Rect2i(FRAME_PX / 4, 0, FRAME_PX / 2, FRAME_PX), fallback)
		return ImageTexture.create_from_image(blob)
	var image: Image = (load(path) as Texture2D).get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		image = image.get_region(used)
	var scale := float(FRAME_PX) / float(maxi(image.get_width(), image.get_height()))
	image.resize(maxi(int(image.get_width() * scale), 1), maxi(int(image.get_height() * scale), 1), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)


func _capture_all() -> void:
	print("=== high_fidelity_threshold candidates (D82) ===")
	print("figure %.1f m, residents %.4f/m^2, horde %.2f/m^2, 1 wu = %.2f m\n"
			% [FIGURE_METRES, RESIDENT_DENSITY_PER_M2, HORDE_DENSITY_PER_M2,
			1.0 / HexCoord.WORLD_UNITS_PER_REAL_METER])
	for zoom in ZOOMS:
		await _capture(zoom, HORDE_VIEW_FRACTION, "threshold")
	print("")
	for zoom in ENGULF_ZOOMS:
		await _capture(zoom, ENGULF_VIEW_FRACTION, "engulfed")
	print("\nPNGs in %s" % ProjectSettings.globalize_path(OUT_DIR))


func _capture(zoom: float, horde_fraction: float, tag: String) -> void:
	var metres_per_wu := 1.0 / HexCoord.WORLD_UNITS_PER_REAL_METER
	var half_w := (float(WINDOW_SIZE.x) / zoom) * 0.5
	var half_h := (float(WINDOW_SIZE.y) / zoom) * 0.5
	var width_m := half_w * 2.0 * metres_per_wu
	var height_m := half_h * 2.0 * metres_per_wu
	var view_area_m2 := width_m * height_m

	var figure_wu := FIGURE_METRES * HexCoord.WORLD_UNITS_PER_REAL_METER
	var figure_px := figure_wu * zoom

	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = Vector2.ZERO
	_ground.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h)])

	var resident_count := int(view_area_m2 * RESIDENT_DENSITY_PER_M2)
	var horde_area_m2 := view_area_m2 * horde_fraction
	var horde_count := int(horde_area_m2 * HORDE_DENSITY_PER_M2)
	var horde_radius_wu := sqrt(horde_area_m2 / PI) * HexCoord.WORLD_UNITS_PER_REAL_METER
	# An engulfing horde is centred so its disc covers the frame; a partial one is
	# offset so its EDGE is what the shot shows, which is where a player reads size.
	var centre_fraction := Vector2(0.5, 0.5) if horde_fraction >= 1.0 else HORDE_CENTRE_FRACTION
	var horde_centre := Vector2(
		lerpf(-half_w, half_w, centre_fraction.x),
		lerpf(-half_h, half_h, centre_fraction.y))

	_fill_scatter(_residents, resident_count, figure_wu, half_w, half_h)
	_fill_disc(_horde, horde_count, figure_wu, horde_centre, horde_radius_wu)
	_fill_squad(figure_wu, half_w, half_h)

	_caption.text = "zoom %.0f    %.0f x %.0f m on screen    figure %.1f px" % [zoom, width_m, height_m, figure_px]
	var horde_label := "engulfed by %s" if horde_fraction >= 1.0 else "%s in the horde edge"
	_subcaption.text = "%s residents (%.4f/m2)   +   %s   +   %d units" % [
			_commas(resident_count), RESIDENT_DENSITY_PER_M2,
			horde_label % _commas(horde_count), SQUAD_SIZE]

	for i in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var name := "%s_%03d" % [tag, int(zoom)]
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  %-18s zoom %6.1f  %6.0f x %-5.0f m  %5.1f px/figure  %8s residents  %8s horde"
			% [name, zoom, width_m, height_m, figure_px, _commas(resident_count), _commas(horde_count)])


func _fill_scatter(layer: MultiMeshInstance2D, count: int, figure_wu: float, half_w: float, half_h: float) -> void:
	var mm := layer.multimesh
	(mm.mesh as QuadMesh).size = _quad_size(layer.texture, figure_wu)
	mm.instance_count = count
	var buffer := PackedFloat32Array()
	buffer.resize(count * 8)
	for i in count:
		var base := i * 8
		buffer[base] = 1.0
		buffer[base + 3] = _rng.randf_range(-half_w, half_w)
		buffer[base + 5] = 1.0
		buffer[base + 7] = _rng.randf_range(-half_h, half_h)
	mm.buffer = buffer
	# A MultiMeshInstance2D culls against its MultiMesh's AABB and assigning
	# buffer does not recompute one — the defect
	# TacticalEntityLayer._refresh_swarm_batches() records finding by screenshot.
	mm.custom_aabb = AABB(Vector3(-half_w * 2.0, -half_h * 2.0, -1.0),
			Vector3(half_w * 4.0, half_h * 4.0, 2.0))


## sqrt() on the radius spreads a uniform sample over the disc's AREA rather
## than bunching it at the centre — same correction ZombieSwarm._spawn() makes.
func _fill_disc(layer: MultiMeshInstance2D, count: int, figure_wu: float, centre: Vector2, radius: float) -> void:
	var mm := layer.multimesh
	(mm.mesh as QuadMesh).size = _quad_size(layer.texture, figure_wu)
	mm.instance_count = count
	var buffer := PackedFloat32Array()
	buffer.resize(count * 8)
	for i in count:
		var angle := _rng.randf() * TAU
		var r := radius * sqrt(_rng.randf())
		var base := i * 8
		buffer[base] = 1.0
		buffer[base + 3] = centre.x + cos(angle) * r
		buffer[base + 5] = 1.0
		buffer[base + 7] = centre.y + sin(angle) * r
	mm.buffer = buffer
	var reach := radius + figure_wu
	mm.custom_aabb = AABB(Vector3(centre.x - reach, centre.y - reach, -1.0),
			Vector3(reach * 2.0, reach * 2.0, 2.0))


## A squad in loose formation, opposite the horde, so the two are readable
## against each other — "can I tell my units from theirs at this zoom" is half
## the threshold question and neither density answers it alone.
func _fill_squad(figure_wu: float, half_w: float, half_h: float) -> void:
	for child in _squad.get_children():
		child.queue_free()
	var quad := _quad_size(_unit_texture, figure_wu)
	var origin := Vector2(lerpf(-half_w, half_w, 0.72), lerpf(-half_h, half_h, 0.68))
	for i in SQUAD_SIZE:
		var sprite := Sprite2D.new()
		sprite.texture = _unit_texture
		var column := i % 4
		var row := i / 4
		sprite.position = origin + Vector2(float(column) * figure_wu * 1.4, float(row) * figure_wu * 1.4)
		sprite.scale = Vector2(quad.x / float(_unit_texture.get_width()), quad.y / float(_unit_texture.get_height()))
		_squad.add_child(sprite)


## Quad sized from the texture's real dimensions so its LONGER axis lands on the
## figure's metric height — a QuadMesh's UVs span its own `size` regardless of
## the texture's pixel dimensions, so a fixed square stretches non-square art.
## Same rule TacticalEntityLayer._apply_swarm_look() applies.
func _quad_size(texture: Texture2D, figure_wu: float) -> Vector2:
	var longest := maxf(texture.get_width(), texture.get_height())
	return Vector2(texture.get_width(), texture.get_height()) * (figure_wu / longest)


static func _commas(value: int) -> String:
	var digits := str(value)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
