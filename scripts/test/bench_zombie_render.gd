extends Node2D

## Measures what it costs to RENDER a crowd, as opposed to what it costs to
## move one. Answers the threshold question D76-D80 left open: at what zoom may
## individual figures appear without the frame breaking, and does driving a
## walk cycle from a sprite sheet change that answer.
##
## Run (NOT --headless -- under the dummy rendering server a MultiMesh backs no
## storage at all, so a headless run measures an empty scene and reports it as
## fast; ZombieSwarm's own doc comment records the same constraint):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/bench_zombie_render.tscn
##
## bench_zombie_swarm.gd measures ZombieSwarm.step() -- CPU, no render, 2.79 ms
## at 60,000. That number is why the tactical layer was believed affordable. It
## does not answer the question that decides
## CameraController.high_fidelity_threshold, because it leaves out both fill
## rate and the per-frame buffer handoff to the renderer.
##
## **Vsync is disabled.** A windowed Godot app is frame-capped by default, so
## every row inside budget would report ~16.6 ms and the ceiling would be
## invisible.
##
## **Frame time is wall clock, and it is the only timing reported.** An earlier
## cut of this bench printed Performance.TIME_PROCESS beside it and the column
## was worthless -- Godot updates that monitor roughly once a second, so it read
## a constant 94.97 ms next to a measured 0.23 ms frame. Deleted rather than
## explained.
##
## Four sweeps:
##
##   COUNT      pure render: how many figures draw at all, static vs animated
##   OVERDRAW   pure render: what overlapping costs
##   SIMULATED  the real frame -- live ZombieSwarm crowds stepped and handed to
##              the renderer every frame, at the count each zoom actually
##              implies. This is the row that decides the threshold.
##   ANIMATED   the same, against a stride-12 buffer carrying a per-instance
##              animation phase (see _WideCrowd)
##
## No walk-cycle art exists yet, so the sheet is SYNTHETIC: one real zombie PNG
## cropped, downscaled to FRAME_PX and tiled ANIM_FRAMES across. Honest for a
## cost measurement -- what is timed is the per-fragment sheet lookup and the
## per-instance custom-data fetch, neither of which cares whether the frames
## differ -- and dishonest for anything else. Do not read these rows as
## "animation works".

const FRAME_BUDGET_MS: float = 16.6

## Frames discarded after a case changes. instance_count reallocates and the
## first frames after it pay for that rather than for drawing.
const WARM_FRAMES: int = 20
const TIMED_FRAMES: int = 60
const DELTA: float = 1.0 / 60.0

## Fixed so a row's numbers do not depend on which monitor this ran on. Matches
## project.godot's own viewport rather than the desktop.
const WINDOW_SIZE := Vector2i(1280, 720)

## FRAME_PX comes from what D76 asks for -- a 3.5 m figure reads at 46 px at
## zoom 128 -- with headroom, NOT from the 2048x2048 the pipeline currently
## renders. That size is a separate finding (backlog: "Texture import is
## uncompressed"); using it here would measure that defect instead of this one.
const FRAME_PX: int = 128
const ANIM_FRAMES: int = 4
const ANIM_FPS: float = 8.0

## D76: a 1.8 m human drawn at the RTS convention of ~2x life so it reads at all.
const FIGURE_METRES: float = 3.5

## Densest case after D79 clusters residents onto URBAN sub-cells: a London hex
## at order 5e5 over ~60% of its 64.7 km^2. Every derived-count row uses this
## rather than a round number, so the counts below are what the map really asks
## for at each zoom.
const LONDON_URBAN_DENSITY_PER_M2: float = 0.0129

## The simulation must carry figures just outside the viewport or they pop into
## view at its edge.
const OFFSCREEN_MARGIN: float = 1.6

const COUNT_SWEEP: Array[int] = [1_000, 5_000, 10_000, 20_000, 40_000, 60_000, 120_000]

const OVERDRAW_PX: Array[int] = [4, 8, 16, 32, 64]
const OVERDRAW_COUNT: int = 20_000

## 2.0 and 12.0 were high_fidelity_threshold and max_zoom when this bench ran;
## its own results moved them to 48.0 and 128.0 (D85, D76). Kept as measured —
## the ladder is what located the answer and re-running it on the new
## constants would delete the evidence for them.
const SIM_ZOOMS: Array[float] = [2.0, 5.0, 7.5, 12.0, 20.0, 32.0, 67.0, 128.0]

## Above this many entities the setup cost alone runs into minutes and the row
## teaches nothing the row below it did not. Reported as skipped rather than
## silently dropped.
const SIM_COUNT_CEILING: int = 500_000


## A crowd whose render buffer carries MultiMesh custom data, so each instance
## can hold its own animation phase. ZombieSwarm writes TRANSFORM_FLOATS = 8;
## a MultiMesh with use_custom_data needs 12.
##
## Duplicated here rather than changing ZombieSwarm, because the point is to
## COST the proposed change before making it. The loop mirrors
## ZombieSwarm.step()'s: same slicing, same spread branch, same "write the
## origin, leave the basis alone" per-instance work. The only difference is the
## stride -- which is the entire question. Phase is written once at spawn and
## never touched again, so if these rows match the stride-8 rows, animation
## costs memory and nothing else.
class _WideCrowd:
	const STRIDE: int = 12
	const ORIGIN_X: int = 3
	const ORIGIN_Y: int = 7
	const PHASE: int = 8

	var anchor: Vector2 = Vector2.ZERO
	var spread: float = 64.0
	var slices: int = 1

	var _position: PackedVector2Array = PackedVector2Array()
	var _velocity: PackedVector2Array = PackedVector2Array()
	var _buffer: PackedFloat32Array = PackedFloat32Array()
	var _count: int = 0
	var _slice: int = 0

	func setup(count: int, p_anchor: Vector2, p_spread: float, rng: RandomNumberGenerator) -> void:
		_count = count
		anchor = p_anchor
		spread = p_spread
		_position.resize(count)
		_velocity.resize(count)
		_buffer.resize(count * STRIDE)
		for i in count:
			var angle := rng.randf() * TAU
			var dir := Vector2(cos(angle), sin(angle))
			_position[i] = anchor + dir * (spread * sqrt(rng.randf()))
			_velocity[i] = dir * ZombieSwarm.MILL_SPEED
			var base := i * STRIDE
			_buffer[base] = 1.0
			_buffer[base + 5] = 1.0
			_buffer[base + PHASE] = rng.randf()  ## Written once. Never rewritten.
			_buffer[base + ORIGIN_X] = _position[i].x
			_buffer[base + ORIGIN_Y] = _position[i].y

	func buffer() -> PackedFloat32Array:
		return _buffer

	func step(delta: float) -> void:
		if _count == 0:
			return
		var slice_total := maxi(slices, 1)
		_slice = (_slice + 1) % slice_total
		var dt := minf(delta, ZombieSwarm.MAX_STEP_SECONDS) * float(slice_total)
		var spread_squared := spread * spread
		var positions := _position
		_position = PackedVector2Array()  ## Drop the reference so the loop writes in place.
		var i := _slice
		while i < _count:
			var p: Vector2 = positions[i] + _velocity[i] * dt
			var offset := anchor - p
			var distance_squared := offset.length_squared()
			var dir: Vector2
			var speed: float
			if distance_squared > spread_squared:
				dir = offset / sqrt(distance_squared)
				speed = ZombieSwarm.CHASE_SPEED
			else:
				dir = Vector2(-_velocity[i].y, _velocity[i].x).normalized()
				speed = ZombieSwarm.MILL_SPEED
			positions[i] = p
			var base := i * STRIDE
			_buffer[base + ORIGIN_X] = p.x
			_buffer[base + ORIGIN_Y] = p.y
			_velocity[i] = dir * speed
			i += slice_total
		_position = positions


var _cases: Array[Dictionary] = []
var _case_index: int = 0
var _frames_in_case: int = 0
var _samples: Array[float] = []
var _sim_samples: Array[float] = []
var _last_frame_usec: int = 0

var _mmi: MultiMeshInstance2D
var _camera: Camera2D
var _static_texture: Texture2D
var _sheet_texture: Texture2D
var _anim_material: ShaderMaterial

var _swarms: Array[ZombieSwarm] = []
var _wide: _WideCrowd = null

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = WINDOW_SIZE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_rng.seed = 20260907

	_static_texture = _build_sheet(1)
	_sheet_texture = _build_sheet(ANIM_FRAMES)
	_anim_material = _build_anim_material()

	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()

	_mmi = MultiMeshInstance2D.new()
	add_child(_mmi)

	_build_cases()

	print("=== Crowd cost: render, and the whole frame (windowed, vsync off) ===")
	print("window %dx%d, budget %.1f ms/frame, median of %d timed frames after %d warm"
			% [WINDOW_SIZE.x, WINDOW_SIZE.y, FRAME_BUDGET_MS, TIMED_FRAMES, WARM_FRAMES])
	print("sheet %d px/frame x %d frames, figure %.1f m, 1 wu = %.2f m"
			% [FRAME_PX, ANIM_FRAMES, FIGURE_METRES, 1.0 / HexCoord.WORLD_UNITS_PER_REAL_METER])
	print("counts in the SIMULATED/ANIMATED sweeps are DERIVED from London density, not chosen\n")

	_apply_case(0)
	_last_frame_usec = Time.get_ticks_usec()


## One horizontal strip of `frames` copies of the real zombie art, downscaled to
## FRAME_PX. Real art rather than a flat quad so alpha coverage, and therefore
## blending cost, is the shape the game will really draw. Tight-cropped first:
## the source PNG carries ~78% empty margin (backlog: sprite-crop item), and
## scaling that padding down would measure a sprite far smaller than FRAME_PX
## claims. Falls back to a generated blob so this still runs on a checkout whose
## assets have not been rendered.
func _build_sheet(frames: int) -> Texture2D:
	var frame_image: Image
	var source := ZombieVisuals.zombie_texture(0, GameEnums.Facing8.S)
	if source:
		frame_image = source.get_image()
		frame_image.decompress()
		frame_image.convert(Image.FORMAT_RGBA8)
		var used := frame_image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			frame_image = frame_image.get_region(used)
		frame_image.resize(FRAME_PX, FRAME_PX, Image.INTERPOLATE_BILINEAR)
	else:
		frame_image = Image.create(FRAME_PX, FRAME_PX, false, Image.FORMAT_RGBA8)
		frame_image.fill(Color(0.33, 0.4, 0.27, 0.0))
		frame_image.fill_rect(Rect2i(FRAME_PX / 4, 0, FRAME_PX / 2, FRAME_PX), Color(0.33, 0.4, 0.27, 1.0))

	var sheet := Image.create(FRAME_PX * frames, FRAME_PX, false, Image.FORMAT_RGBA8)
	for f in frames:
		sheet.blit_rect(frame_image, Rect2i(0, 0, FRAME_PX, FRAME_PX), Vector2i(FRAME_PX * f, 0))
	return ImageTexture.create_from_image(sheet)


## Per-instance frame index from MultiMesh custom data. This is the whole
## proposal being costed: the phase is written ONCE at spawn and the frame
## advances from TIME on the GPU, so a walking crowd costs no per-frame CPU.
func _build_anim_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float frames = 4.0;
uniform float anim_fps = 8.0;

varying flat float phase;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float f = floor(mod(TIME * anim_fps + phase * frames, frames));
	vec2 sheet_uv = vec2((UV.x + f) / frames, UV.y);
	COLOR = texture(TEXTURE, sheet_uv);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("frames", float(ANIM_FRAMES))
	material.set_shader_parameter("anim_fps", ANIM_FPS)
	return material


func _build_cases() -> void:
	for animated in [false, true]:
		for n in COUNT_SWEEP:
			_cases.append({"sweep": "COUNT", "animated": animated, "simulate": false,
					"count": n, "figure_px": 24.0, "zoom": 1.0})
	for px in OVERDRAW_PX:
		_cases.append({"sweep": "OVERDRAW", "animated": true, "simulate": false,
				"count": OVERDRAW_COUNT, "figure_px": float(px), "zoom": 1.0})
	for sweep in ["SIMULATED", "ANIMATED"]:
		for zoom in SIM_ZOOMS:
			_cases.append({"sweep": sweep, "animated": sweep == "ANIMATED", "simulate": true,
					"count": _count_at_zoom(zoom),
					"figure_px": FIGURE_METRES * HexCoord.WORLD_UNITS_PER_REAL_METER * zoom,
					"zoom": zoom})


## What a London-density hex really puts in frame at `zoom`, plus the offscreen
## margin. Screen area falls as 1/zoom^2, which is the whole reason moving the
## threshold deeper is expected to work.
func _count_at_zoom(zoom: float) -> int:
	var metres_per_wu := 1.0 / HexCoord.WORLD_UNITS_PER_REAL_METER
	var width_m := (float(WINDOW_SIZE.x) / zoom) * metres_per_wu
	var height_m := (float(WINDOW_SIZE.y) / zoom) * metres_per_wu
	return int(width_m * height_m * LONDON_URBAN_DENSITY_PER_M2 * OFFSCREEN_MARGIN)


func _apply_case(index: int) -> void:
	var c := _cases[index]
	var animated: bool = c["animated"]
	var simulate: bool = c["simulate"]
	var count: int = c["count"]
	var figure_px: float = c["figure_px"]
	var zoom: float = c["zoom"]

	_swarms.clear()
	_wide = null

	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = Vector2.ZERO

	if simulate and count > SIM_COUNT_CEILING:
		_frames_in_case = 0
		_samples.clear()
		_sim_samples.clear()
		return  ## Reported as skipped by _report_case().

	var half_w := (float(WINDOW_SIZE.x) / zoom) * 0.5
	var half_h := (float(WINDOW_SIZE.y) / zoom) * 0.5
	var spread := maxf(half_w, half_h)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
	mm.use_custom_data = animated
	var quad := QuadMesh.new()
	# Sized in WORLD units so the on-screen result is figure_px at this zoom --
	# the same relationship TacticalEntityLayer._apply_swarm_look() maintains.
	quad.size = Vector2.ONE * (figure_px / zoom)
	mm.mesh = quad
	mm.instance_count = count

	if simulate:
		if animated:
			_wide = _WideCrowd.new()
			_wide.slices = ZombieSwarm.slices_for(count)
			_wide.setup(count, Vector2.ZERO, spread, _rng)
			mm.buffer = _wide.buffer()
		else:
			var swarm := ZombieSwarm.new(1)
			swarm.anchor = Vector2.ZERO
			swarm.spread = spread
			swarm.slices = ZombieSwarm.slices_for(count)
			swarm.set_count(count)
			_swarms.append(swarm)
			mm.buffer = swarm.buffer()
	else:
		mm.buffer = _build_buffer(count, animated, zoom)

	_mmi.multimesh = mm
	_mmi.texture = _sheet_texture if animated else _static_texture
	_mmi.material = _anim_material if animated else null

	# Without this every instance measures as the identity transform and the
	# node culls against a 10x10 box at the origin -- the defect
	# TacticalEntityLayer._refresh_swarm_batches() records finding by
	# screenshot. A bench that hit it would report an empty screen as very fast.
	var reach_w := half_w + quad.size.x
	var reach_h := half_h + quad.size.y
	mm.custom_aabb = AABB(Vector3(-reach_w, -reach_h, -1.0), Vector3(reach_w * 2.0, reach_h * 2.0, 2.0))

	_frames_in_case = 0
	_samples.clear()
	_sim_samples.clear()


## Scattered uniformly across the visible rect rather than in a disc: the
## question is what a screenful costs, and a disc inscribed in the viewport
## would leave the corners empty and undercount by ~21%.
func _build_buffer(count: int, animated: bool, zoom: float) -> PackedFloat32Array:
	var stride := 12 if animated else 8
	var buffer := PackedFloat32Array()
	buffer.resize(count * stride)
	var half_w := (float(WINDOW_SIZE.x) / zoom) * 0.5
	var half_h := (float(WINDOW_SIZE.y) / zoom) * 0.5
	for i in count:
		var base := i * stride
		buffer[base] = 1.0
		buffer[base + 3] = _rng.randf_range(-half_w, half_w)
		buffer[base + 5] = 1.0
		buffer[base + 7] = _rng.randf_range(-half_h, half_h)
		if animated:
			buffer[base + 8] = _rng.randf()
	return buffer


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now

	var c := _cases[_case_index]
	var skipped: bool = c["simulate"] and int(c["count"]) > SIM_COUNT_CEILING

	var sim_ms := 0.0
	if not skipped and c["simulate"]:
		var t0 := Time.get_ticks_usec()
		if _wide:
			_wide.step(DELTA)
			_mmi.multimesh.buffer = _wide.buffer()
		else:
			for swarm in _swarms:
				swarm.step(DELTA)
				_mmi.multimesh.buffer = swarm.buffer()
		sim_ms = float(Time.get_ticks_usec() - t0) / 1000.0

	_frames_in_case += 1
	if _frames_in_case > WARM_FRAMES:
		_samples.append(frame_ms)
		_sim_samples.append(sim_ms)

	if not skipped and _samples.size() < TIMED_FRAMES:
		return

	_report_case(_case_index, skipped)
	_case_index += 1
	if _case_index >= _cases.size():
		_finish()
		return
	_apply_case(_case_index)


func _report_case(index: int, skipped: bool) -> void:
	var c := _cases[index]
	if index == 0 or _cases[index - 1]["sweep"] != c["sweep"]:
		_print_header(c["sweep"])

	var count: int = c["count"]
	var figure_px: float = c["figure_px"]

	if skipped:
		print("  zoom %6.1f  %8d figures  %5.1f px each   -- skipped, past the %d setup ceiling"
				% [c["zoom"], count, figure_px, SIM_COUNT_CEILING])
		return

	var ms := _median(_samples)
	var sim_ms := _median(_sim_samples)
	var coverage := float(count) * figure_px * figure_px / float(WINDOW_SIZE.x * WINDOW_SIZE.y)
	var verdict := "ok" if ms <= FRAME_BUDGET_MS else "OVER BUDGET"

	match c["sweep"]:
		"COUNT":
			print("  %s  %7d figures  %8.2f ms  %6.2fx cover  %s"
					% ["animated" if c["animated"] else "static  ", count, ms, coverage, verdict])
		"OVERDRAW":
			print("  %5.0f px figure  %7d figures  %8.2f ms  %6.2fx cover  %s"
					% [figure_px, count, ms, coverage, verdict])
		_:
			print("  zoom %6.1f  %8d figures  %5.1f px each  sim %7.2f  total %8.2f ms  %s"
					% [c["zoom"], count, figure_px, sim_ms, ms, verdict])


func _print_header(sweep: String) -> void:
	match sweep:
		"COUNT":
			print("COUNT -- pure render, fixed 24 px figures, nothing simulated")
		"OVERDRAW":
			print("\nOVERDRAW -- pure render, %d figures, growing on-screen size" % OVERDRAW_COUNT)
		"SIMULATED":
			print("\nSIMULATED -- live ZombieSwarm crowds stepped and uploaded every frame (stride 8)")
			print("  this is the real frame; the first row inside budget is the earliest defensible threshold")
		"ANIMATED":
			print("\nANIMATED -- the same, stride 12 with a per-instance animation phase")
			print("  matching the SIMULATED rows => animation costs memory and nothing else")


func _finish() -> void:
	print("\nhigh_fidelity_threshold was 2.0 when this ran and is 48.0 now (D85).")
	print("A figure is legible at roughly 10-12 px, which the px column locates on this ladder.")
	get_tree().quit(0)


## Median, not mean: one GC pause or compositor hitch must not be what a
## threshold decision is made on. Same rule bench_zombie_swarm.gd applies.
static func _median(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
