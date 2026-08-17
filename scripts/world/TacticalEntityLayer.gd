class_name TacticalEntityLayer
extends Node2D

## Individual-figure rendering at Tactical zoom: a squad of
## UnitInstance.SQUAD_SIZE figures for Tier 0-3 units, one larger model for
## Tier 4-5 (named vehicles), and a capped cluster of individual zombie
## figures per Horde. StrategicOverlayManager's own unit/horde markers hide
## entirely at Tactical zoom (visible = not is_tactical), so without this
## class a unit or horde standing on a hex would render as nothing once the
## camera crosses into Tactical zoom.
##
## Not gated on LocalDetailManager's hex-hydration set (settled/frontier-only)
## the way TacticalHexView's terrain/props/buildings are — a unit or horde
## crossing an otherwise-abstract wilderness hex still needs to be visible
## while the player is looking at it. Only camera zoom mode gates this
## layer; entities render at the same HexCoord.axial_to_world(hex_coord) +
## local_position world point props/buildings use. Read fresh every frame
## regardless of how that value is written, so continuous real-time motion
## (MovementStepper) needed zero changes here.
##
## Squad headcount (UnitInstance.get_squad_headcount()) and zombie figure
## count are DERIVED, not separately tracked — no signal covers every way
## current_hp/size can change (combat, Garrison healing, casualty
## accumulation), so this class re-polls UnitManager/HordeManager's live
## instance lists every frame while visible and diffs against what it drew
## last time, same "cheap self-healing full recompute" shape
## LocalDetailManager uses for its own camera-driven neighborhood refresh —
## only redrawing a group's figures when its (headcount, fidelity) pair
## actually changed, not every frame.
##
## Parented as a WorldRoot sibling, same as every other Tactical-adjacent
## overlay (LocalDetailManager, StrategicOverlayManager, UnitCommandController):
## shares the coordinate space, including CameraController's isometric transform.
##
## **Rendering at scale:** HIGH-fidelity zombie figures — the only path this
## project expects to reach horde-scale counts — draw through
## ZombieVisuals.VARIANT_COUNT * FacingUtil.COUNT (3*8=24) shared
## MultiMeshInstance2D batch layers (_zombie_batch_layers, built once in
## _ready(), repopulated every frame by _rebuild_zombie_batches()) instead
## of one Polygon2D/Sprite2D scene node PER FIGURE. A MultiMesh instance is
## a transform written into a GPU buffer, not a scene-tree node the engine
## individually tracks/processes/draws — that per-node overhead, not the
## per-frame position math, is what made the old approach fall over before
## real horde-scale counts. LOW/MEDIUM zombie rendering and every unit
## figure are unchanged, still one node each — none come near the count
## where batching matters.
##
## **Multi-Tier Visual Fidelity:** this class owns all three of Tactical
## zoom's internal fidelity bands (GameEnums.TacticalFidelity), driven by
## CameraController.tactical_fidelity_changed — HIGH is the original
## per-figure rendering; LOW/MEDIUM are coarser bands as the camera nears
## tactical_zoom_threshold. A fidelity change clears both headcount caches
## outright (their cached value encodes fidelity too, via a Vector2i key) so
## every currently-tracked group redraws under the new band on the next
## _process() poll.
##
## **Unit/zombie art:** `_build_unit_figure()`/`_build_role_marker()` both
## consult `UnitVisuals.unit_texture()` and draw a real sprite in place of
## the flat procedural shape wherever a PNG has been authored — HIGH and
## MEDIUM only. LOW stays a uniform per-category blob (it was only ever
## meant to distinguish "unit vs. building vs. zombie", not unit types).
##
## **Facing:** units and hordes both get an 8-way GameEnums.Facing8, derived
## every frame from movement (_advance_facing()) — see that function's own
## doc comment for why it's derived rather than read from stored state. A
## Horde has no per-figure position (see ZombieVisuals.zombie_texture()'s
## doc comment), so it's one facing for the whole horde, not per-figure.

const FIGURE_COLOR := Color(0.85, 0.8, 0.7)    ## Player-unit squad figures (HIGH) — pale "uniform" tone, distinct from terrain/prop/building colors.
const VEHICLE_COLOR := Color(0.5, 0.46, 0.32)  ## Tier 4-5 single-model units (HIGH) — heavier, darker than a squad figure.
const ZOMBIE_COLOR := Color(0.33, 0.4, 0.27)   ## Sickly green-grey, distinct from both.

const FIGURE_RADIUS := 6.0
const VEHICLE_RADIUS := 16.0
const ZOMBIE_RADIUS := 5.0
const FIGURE_SPREAD := 20.0  ## How far individual squad/zombie figures scatter from their entity's own local_position.

## World units of frame-to-frame movement below which a stale facing is
## kept rather than recomputed — a stationary unit/horde's position still
## carries floating-point noise, and recomputing from that would flicker
## facing on something that isn't actually moving.
const MIN_FACING_MOVE_DISTANCE := 1.0

## Performance safety net for the batched HIGH-fidelity zombie renderer.
## MAX_RENDERED_ZOMBIES_PER_HORDE keeps one gigantic horde from consuming
## the whole frame's render budget; MAX_TOTAL_RENDERED_ZOMBIES caps the
## AGGREGATE across every horde combined, the number that actually bounds
## GPU/CPU cost regardless of how the population is split across however
## many Horde instances exist at once (merges/splits). A per-horde-only cap
## alone would still be an unbounded-TOTAL gap. LOW/MEDIUM's own much
## smaller fixed counts are untouched by either cap.
const MAX_RENDERED_ZOMBIES_PER_HORDE := 1000
const MAX_TOTAL_RENDERED_ZOMBIES := 5000

## LOW fidelity: one uniform blob per unit regardless of role/tier, one per
## horde regardless of size. Unit blob is a circle (matches HIGH's own
## figure shape); the horde blob is a DIAMOND — the same shape
## StrategicOverlayManager's own horde marker uses at Strategic zoom, so
## "unit vs zombie" reads by shape, not color alone, at the lowest fidelity too.
const LOW_UNIT_RADIUS := 10.0
const LOW_ZOMBIE_RADIUS := 10.0

## MEDIUM fidelity: one marker per unit, shaped by role (circle/triangle/
## diamond — shape distinguishes, not just color) and sized by tier. Hordes
## get a small FIXED-size cluster, not the true headcount.
const MEDIUM_UNIT_BASE_RADIUS := 7.0
const MEDIUM_UNIT_TIER_STEP := 1.5  ## Added per definition.tier, so a Tier 5 marker reads visibly larger than a Tier 0 one.
const MEDIUM_MELEE_COLOR := Color(0.72, 0.32, 0.28)   ## Rust red.
const MEDIUM_RANGED_COLOR := Color(0.35, 0.55, 0.78)  ## Blue.
const MEDIUM_SPECIAL_COLOR := Color(0.62, 0.5, 0.78)  ## Violet.
const MEDIUM_ZOMBIE_CLUSTER_SIZE := 5

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Optional — unset renders every horde regardless of vision.
@export var camera_path: NodePath

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController

var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH

var _unit_groups: Dictionary = {}      # int (UnitInstance.id) -> Node2D
var _unit_draw_keys: Dictionary = {}   # int (UnitInstance.id) -> Vector2i(headcount, fidelity), last-drawn
var _horde_groups: Dictionary = {}     # int (Horde.id) -> Node2D
var _horde_draw_keys: Dictionary = {}  # int (Horde.id) -> Vector2i(display_count, fidelity), last-drawn

## Facing tracking — see _advance_facing(). Kept as separate id-keyed
## Dictionaries (not folded into _unit_groups' Node2D, e.g. via metadata)
## since units and hordes each need their own last-position/facing pair and
## both get cleaned up alongside their existing *_draw_keys entries.
var _unit_last_position: Dictionary = {}  # int (UnitInstance.id) -> Vector2
var _unit_facing: Dictionary = {}         # int (UnitInstance.id) -> GameEnums.Facing8
var _horde_last_position: Dictionary = {} # int (Horde.id) -> Vector2
var _horde_facing: Dictionary = {}        # int (Horde.id) -> GameEnums.Facing8

## HIGH-fidelity zombie batch renderer — one layer per (variant, facing)
## pair, flat-indexed as `variant * FacingUtil.COUNT + facing` (see
## _zombie_batch_index()). A whole Horde shares one facing (Horde has no
## per-figure position, only per-figure scatter offsets — see
## ZombieVisuals.zombie_texture()'s own doc comment), so every figure in a
## batch signature list still resolves to exactly one texture per layer,
## same as the pre-directional VARIANT_COUNT-only version this replaced.
var _zombie_batch_layers: Array[MultiMeshInstance2D] = []
var _last_zombie_batch_signature: Array = []  ## Dirty-check cache for _rebuild_zombie_batches().

func _ready() -> void:
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
	if fog_of_war_manager_path != NodePath():
		_fog_of_war_manager = get_node(fog_of_war_manager_path)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		_camera.tactical_fidelity_changed.connect(_on_fidelity_changed)
		visible = _camera.is_tactical_zoom()
		_fidelity = _camera.get_tactical_fidelity()

	for variant in range(ZombieVisuals.VARIANT_COUNT):
		for facing in range(FacingUtil.COUNT):
			_zombie_batch_layers.append(_build_zombie_batch_layer(variant, facing as GameEnums.Facing8))

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_units()
	_refresh_hordes()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical

## A band change alone doesn't change the map's true headcount/size numbers,
## so the plain per-entity redraw-skip check would never notice — clearing
## both caches forces every currently-tracked group to redraw under the new
## band next poll.
func _on_fidelity_changed(fidelity: GameEnums.TacticalFidelity) -> void:
	_fidelity = fidelity
	_unit_draw_keys.clear()
	_horde_draw_keys.clear()

## --- Units (squads / single vehicle models / role markers / blobs) --------

func _refresh_units() -> void:
	if not _unit_manager:
		return
	var seen: Dictionary = {}  # int -> true
	for instance in _unit_manager.get_all_units():
		seen[instance.id] = true
		if not _unit_groups.has(instance.id):
			var group := Node2D.new()
			add_child(group)
			_unit_groups[instance.id] = group
		_update_unit_group(instance)
	for id in _unit_groups.keys():
		if not seen.has(id):
			_unit_groups[id].queue_free()
			_unit_groups.erase(id)
			_unit_draw_keys.erase(id)
			_unit_last_position.erase(id)
			_unit_facing.erase(id)

func _update_unit_group(instance: UnitInstance) -> void:
	var group: Node2D = _unit_groups[instance.id]
	group.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position

	var facing_changed := _advance_facing(instance.id, group.position, _unit_last_position, _unit_facing)

	var headcount := instance.get_squad_headcount()
	var draw_key := Vector2i(headcount, _fidelity)
	if _unit_draw_keys.get(instance.id, Vector2i(-1, -1)) == draw_key:
		# Headcount/fidelity unchanged — the usual case while a unit just
		# walks in a straight line. Only a facing change (usually every
		# frame while turning) needs anything done here, and cheaply: swap
		# existing Sprite2D children's texture in place rather than the
		# full free-and-rebuild below, which would turn "unit changed
		# direction" into per-figure node churn every frame.
		if facing_changed and _fidelity != GameEnums.TacticalFidelity.LOW:
			_retexture_unit_group(group, instance, _unit_facing[instance.id])
		return
	_unit_draw_keys[instance.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if headcount <= 0:
		return  # Destroyed this frame, about to be removed via unit_removed — draw nothing rather than a stale figure.

	var facing: GameEnums.Facing8 = _unit_facing[instance.id]
	match _fidelity:
		GameEnums.TacticalFidelity.LOW:
			# Not UnitVisuals-aware, even where art exists — LOW is a
			# uniform per-category blob by design ("unit vs. building vs.
			# zombie", not unit-from-unit).
			group.add_child(_build_figure(FIGURE_COLOR, LOW_UNIT_RADIUS, Vector2.ZERO))
		GameEnums.TacticalFidelity.MEDIUM:
			group.add_child(_build_role_marker(instance, facing))
		_:  # HIGH — UnitVisuals-aware.
			if instance.is_squad_rendered():
				for i in range(headcount):
					group.add_child(_build_unit_figure(instance, facing, FIGURE_RADIUS, _scatter_offset(i, headcount, instance.id), FIGURE_COLOR))
			else:
				group.add_child(_build_unit_figure(instance, facing, VEHICLE_RADIUS, Vector2.ZERO, VEHICLE_COLOR))

## Facing-only update path for a group whose figures already exist (see
## _update_unit_group()'s draw_key-unchanged branch) — walks existing
## Sprite2D children and swaps their texture, leaves Polygon2D fallback
## shapes (no directional art authored yet) and everything else untouched.
func _retexture_unit_group(group: Node2D, instance: UnitInstance, facing: GameEnums.Facing8) -> void:
	var texture := UnitVisuals.unit_texture(instance.definition.unit_type, facing)
	if not texture:
		return
	for child in group.get_children():
		if child is Sprite2D:
			child.texture = texture

## Real per-unit-type sprite art (UnitVisuals.unit_texture()) in place of
## the flat circle where authored, sized to the same diameter the fallback
## circle would use so real art slots into the existing squad-ring/vehicle
## sizing with no other layout change. Falls back to _build_figure()'s flat
## circle for any type with no PNG authored yet. Uses Sprite2D rather than
## TacticalHexView's Polygon2D-quad-with-explicit-uv approach — there's no
## pre-existing polygon shape to texture here (figures are built ad hoc), so
## a plain sprite scaled to the target diameter is simpler and equally correct.
func _build_unit_figure(instance: UnitInstance, facing: GameEnums.Facing8, radius: float, offset: Vector2, fallback_color: Color) -> Node2D:
	var texture := UnitVisuals.unit_texture(instance.definition.unit_type, facing)
	if not texture:
		return _build_figure(fallback_color, radius, offset)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = offset
	var largest_dim := maxf(texture.get_width(), texture.get_height())
	sprite.scale = Vector2.ONE * ((radius * 2.0) / largest_dim)
	return sprite

## MEDIUM fidelity's role/tier marker. Real art, when authored, replaces the
## procedural shape too — the SAME texture HIGH fidelity uses, scaled to
## this tier's smaller radius rather than a separate MEDIUM-specific asset
## (one generated image per unit, reused at both fidelity bands). Falls back
## to the shape-by-role marker (never color alone) when no art exists yet.
func _build_role_marker(instance: UnitInstance, facing: GameEnums.Facing8) -> Node2D:
	var radius := MEDIUM_UNIT_BASE_RADIUS + float(instance.definition.tier) * MEDIUM_UNIT_TIER_STEP
	var texture := UnitVisuals.unit_texture(instance.definition.unit_type, facing)
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * ((radius * 2.0) / largest_dim)
		return sprite
	var shape := Polygon2D.new()
	match instance.definition.role:
		GameEnums.UnitRole.MELEE:
			shape.color = MEDIUM_MELEE_COLOR
			shape.polygon = _circle_points(radius)
		GameEnums.UnitRole.RANGED:
			shape.color = MEDIUM_RANGED_COLOR
			shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius * 0.87, radius * 0.5), Vector2(-radius * 0.87, radius * 0.5)])  # Triangle.
		_:  # SPECIAL
			shape.color = MEDIUM_SPECIAL_COLOR
			shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])  # Diamond.
	return shape

## Real zombie art (ZombieVisuals.zombie_texture()), same Sprite2D-scaled-to-
## diameter approach _build_unit_figure() uses, falling back individually
## per figure to the flat circle. `horde_id + index` seeds which of
## ZombieVisuals.VARIANT_COUNT looks this figure gets — deterministic (same
## figure always looks the same across redraws) but varied across a horde's
## own figures so a cluster doesn't read as identical clones.
func _build_zombie_figure(horde_id: int, index: int, offset: Vector2, facing: GameEnums.Facing8) -> Node2D:
	var texture := ZombieVisuals.zombie_texture(horde_id + index, facing)
	if not texture:
		return _build_figure(ZOMBIE_COLOR, ZOMBIE_RADIUS, offset)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = offset
	var largest_dim := maxf(texture.get_width(), texture.get_height())
	sprite.scale = Vector2.ONE * ((ZOMBIE_RADIUS * 2.0) / largest_dim)
	return sprite

## --- Hordes (zombie blobs / clusters) --------------------------------------

func _refresh_hordes() -> void:
	if not _horde_manager:
		return
	var seen: Dictionary = {}  # int -> true
	for horde in _horde_manager.get_all_hordes():
		seen[horde.id] = true
		if not _horde_groups.has(horde.id):
			var group := Node2D.new()
			add_child(group)
			_horde_groups[horde.id] = group
		_update_horde_group(horde)
	for id in _horde_groups.keys():
		if not seen.has(id):
			_horde_groups[id].queue_free()
			_horde_groups.erase(id)
			_horde_draw_keys.erase(id)
			_horde_last_position.erase(id)
			_horde_facing.erase(id)
	# Once per frame, not once per horde — HIGH-fidelity figures don't live
	# under each horde's own `group` node the way LOW/MEDIUM's do.
	_rebuild_zombie_batches()

## Individual zombie figures are live-vision intel, not remembered-terrain
## intel — gated on VISIBLE (Fog of War), a stricter bar than
## TacticalHexView's own at-least-EXPLORED requirement for terrain and
## buildings, matching the Strategic spotted-horde-marker's own "ghost once
## vision is lost" philosophy.
func _update_horde_group(horde: Horde) -> void:
	var group: Node2D = _horde_groups[horde.id]
	group.position = HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	group.visible = _fog_of_war_manager == null or _fog_of_war_manager.is_visible(horde.hex_coord)

	# Computed here (not in _rebuild_zombie_batches()) so it runs once per
	# horde regardless of fidelity — MEDIUM's per-figure sprites and HIGH's
	# batch layers (via _horde_facing, read back in _rebuild_zombie_batches())
	# both need it, and this is the one place both paths already visit.
	var facing_changed := _advance_facing(horde.id, group.position, _horde_last_position, _horde_facing)

	var display_count := _horde_display_count(horde.size)
	var draw_key := Vector2i(display_count, _fidelity)
	if _horde_draw_keys.get(horde.id, Vector2i(-1, -1)) == draw_key:
		# Same reasoning as _update_unit_group()'s own unchanged-draw_key
		# branch: retexture MEDIUM's existing Sprite2D children in place
		# rather than a full rebuild. LOW is never ZombieVisuals-aware and
		# HIGH has no per-horde children at all (batch layers), so only
		# MEDIUM has anything to do here.
		if facing_changed and _fidelity == GameEnums.TacticalFidelity.MEDIUM:
			var facing: GameEnums.Facing8 = _horde_facing[horde.id]
			var children := group.get_children()
			for i in range(children.size()):
				if children[i] is Sprite2D:
					var texture := ZombieVisuals.zombie_texture(horde.id + i, facing)  # Same horde_id+index variant formula _build_zombie_figure() used to build this child originally.
					if texture:
						children[i].texture = texture
		return
	_horde_draw_keys[horde.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if display_count <= 0:
		return

	if _fidelity == GameEnums.TacticalFidelity.LOW:
		# Not ZombieVisuals-aware, even where art exists — same uniform-blob
		# call _update_unit_group() makes for units.
		group.add_child(_build_diamond(ZOMBIE_COLOR, LOW_ZOMBIE_RADIUS))
	elif _fidelity == GameEnums.TacticalFidelity.MEDIUM:
		var facing: GameEnums.Facing8 = _horde_facing[horde.id]
		for i in range(display_count):
			var variance := horde.individual_speed_variance(i)
			group.add_child(_build_zombie_figure(horde.id, i, _scatter_offset(i, display_count, horde.id, FIGURE_SPREAD, variance), facing))
	# else HIGH: rendered through the shared MultiMesh batch layers instead
	# of per-horde child nodes — see _rebuild_zombie_batches() (called once
	# per frame from _refresh_hordes()). Nothing to add here; the clear
	# above already removed any stale LOW/MEDIUM children left from a
	# fidelity change, and `group` still exists to carry this horde's
	# position/fog-visibility for bookkeeping.

## How many individual zombie figures to draw for a horde of `size` — LOW
## collapses to a single blob, MEDIUM shows a small fixed cluster regardless
## of true size, HIGH shows the real (capped) count.
func _horde_display_count(size: int) -> int:
	if size <= 0:
		return 0
	match _fidelity:
		GameEnums.TacticalFidelity.LOW:
			return 1
		GameEnums.TacticalFidelity.MEDIUM:
			return mini(size, MEDIUM_ZOMBIE_CLUSTER_SIZE)
		_:  # HIGH
			return mini(size, MAX_RENDERED_ZOMBIES_PER_HORDE)

## --- GPU-batched HIGH-fidelity zombie rendering -----------------------------

## One shared MultiMeshInstance2D per (ZombieVisuals variant, Facing8) pair
## — VARIANT_COUNT * FacingUtil.COUNT (3*8=24) layers total, each still a
## single draw call for every figure sharing that exact variant+facing,
## across EVERY horde on the map at once. Same MultiMesh constraint as the
## pre-directional 3-layer version this replaced (one texture per layer) —
## going directional just means more layers, not a per-instance texture
## trick (e.g. an atlas + custom-data UV shader), because a whole Horde
## shares one facing (see ZombieVisuals.zombie_texture()'s doc comment):
## every figure a given (variant, facing) layer will ever hold really does
## want the exact same texture, so the simple multi-layer approach already
## established here still fits without a shader. No texture authored for a
## (variant, facing) pair falls back to a solid `modulate` tint
## (ZOMBIE_COLOR) — a MultiMesh has no per-instance shape choice the way a
## lone Polygon2D circle does.
##
## Each layer's quad is sized from ITS OWN texture's real dimensions (not a
## shared flat constant), scaled so the longer axis lands on the same
## ZOMBIE_RADIUS * 2.0 diameter every other rendering path uses — matches
## the aspect-ratio preservation _build_unit_figure()/_build_role_marker()/
## _build_zombie_figure() all apply. A QuadMesh's UVs span its own fixed
## `size` regardless of the texture's real pixel dimensions, so a fixed
## square size would stretch a non-square texture.
func _build_zombie_batch_layer(variant: int, facing: GameEnums.Facing8) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
	mm.use_custom_data = false

	var texture := ZombieVisuals.zombie_texture(variant, facing)
	var mesh := QuadMesh.new()
	if texture:
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		mesh.size = Vector2(texture.get_width(), texture.get_height()) * ((ZOMBIE_RADIUS * 2.0) / largest_dim)
	else:
		mesh.size = Vector2.ONE * (ZOMBIE_RADIUS * 2.0)  ## No art to derive real dimensions from — same square fallback the flat-color case implies.
	mm.mesh = mesh
	mm.instance_count = 0

	var mmi := MultiMeshInstance2D.new()
	mmi.name = "ZombieBatch%d_%s" % [variant, FacingUtil.suffix(facing)]
	mmi.multimesh = mm
	if texture:
		mmi.texture = texture
	else:
		mmi.modulate = ZOMBIE_COLOR
	# z_index is scoped to this node's own children only (every competing
	# node — unit/horde groups included — is also a direct child of this
	# same TacticalEntityLayer, so it only arbitrates among them). Puts the
	# horde ABOVE units deliberately: these layers are created here in
	# _ready(), unconditionally the first children, while every unit/horde
	# group node is only added later from _refresh_units()/_refresh_hordes()
	# (both _process()-driven, after _ready()) — without z_index, Godot
	# draws lower child index first, permanently burying zombie figures
	# under unit sprites at the exact moment (melee contact) seeing the
	# threat matters most.
	mmi.z_index = 1
	add_child(mmi)
	return mmi

## Flat index into _zombie_batch_layers for a given (variant, facing) pair
## — layers are built in _ready() as an outer loop over variant, inner over
## facing, so this must match that nesting exactly.
func _zombie_batch_index(variant: int, facing: GameEnums.Facing8) -> int:
	return variant * FacingUtil.COUNT + facing

## Repopulates every _zombie_batch_layers entry — hordes move continuously
## in general, so every visible figure's transform needs rewriting when
## anything changes; MultiMesh transform writes are the cheap, GPU-side
## operation this approach leans on instead of the engine individually
## processing/drawing one scene node per figure.
##
## Zeroes every layer's instance_count outright (not just skipping the
## rebuild) when not at HIGH fidelity or with no HordeManager wired, so a
## fidelity drop mid-frame can't leave a stale batch rendered underneath
## LOW/MEDIUM's own per-node figures — and invalidates the dirty-check
## signature below so the next HIGH frame always does a real rebuild.
##
## A per-frame signature — (id, hex_coord, local_position, size,
## fog-visibility) per horde, same order get_all_hordes() returns —
## compared against last frame's via a plain Array `==` (GDScript Arrays
## compare by value/content). O(hordes) to build and compare, not O(total
## figures). This specifically matters for a horde frozen by
## stun_seconds_remaining > 0 or ATTACKING an unbreached wall — both leave
## hex_coord/local_position unchanged for extended stretches (a siege can
## grind on for many ticks), so recomputing every figure's scatter offset
## every frame for a horde that isn't visually moving at all would be
## wasted trig/hash work. When the signature matches, this touches nothing
## — MultiMesh instance buffers persist on the GPU side across frames on
## their own.
##
## Same `horde_id + index` variant-assignment formula _build_zombie_figure()
## uses (wrapped mod VARIANT_COUNT here since this function needs the
## variant INDEX up front to know which layer's transform list to append to).
##
## Two render caps applied together: MAX_RENDERED_ZOMBIES_PER_HORDE first
## (per horde), then whatever room remains under MAX_TOTAL_RENDERED_ZOMBIES
## (the aggregate ceiling). Hordes are iterated in HordeManager.get_all_hordes()
## order — deterministic within a frame, not priority-sorted by e.g.
## proximity to the camera; once the aggregate cap is hit, remaining hordes
## render nothing this frame. This allocation can also shift across frames
## (a merge/split/casualty-spawn changing array order can change how much
## budget an unrelated, unmoved horde gets frame to frame) — only reachable
## once total zombie population exceeds MAX_TOTAL_RENDERED_ZOMBIES, unlikely
## at today's starting economy (STARTING_HORDE_COUNT=3 at 10-25 each, no
## ramp-up curve). A stable sort by priority or proportional scaling instead
## of greedy cutoff would be the real fix if this ever matters.
func _rebuild_zombie_batches() -> void:
	if _fidelity != GameEnums.TacticalFidelity.HIGH or not _horde_manager:
		for layer in _zombie_batch_layers:
			layer.multimesh.instance_count = 0
		_last_zombie_batch_signature = []
		return

	var hordes := _horde_manager.get_all_hordes()

	var signature: Array = []
	for horde in hordes:
		var visible := _fog_of_war_manager == null or _fog_of_war_manager.is_visible(horde.hex_coord)
		signature.append([horde.id, horde.hex_coord, horde.local_position, horde.size, visible, _horde_facing.get(horde.id, GameEnums.Facing8.S)])
	if signature == _last_zombie_batch_signature:
		return
	_last_zombie_batch_signature = signature

	var per_layer: Array = []  # Array[Array[Transform2D]], index == _zombie_batch_index(variant, facing)
	for _i in range(_zombie_batch_layers.size()):
		per_layer.append([])

	var total_rendered := 0
	for horde in hordes:
		if total_rendered >= MAX_TOTAL_RENDERED_ZOMBIES:
			break
		if _fog_of_war_manager and not _fog_of_war_manager.is_visible(horde.hex_coord):
			continue  # Same live-vision gate _update_horde_group()'s own group.visible applies for LOW/MEDIUM.
		var display_count := mini(horde.size, MAX_RENDERED_ZOMBIES_PER_HORDE)
		display_count = mini(display_count, MAX_TOTAL_RENDERED_ZOMBIES - total_rendered)
		if display_count <= 0:
			continue
		var horde_facing: GameEnums.Facing8 = _horde_facing.get(horde.id, GameEnums.Facing8.S)  ## Whole horde shares one facing — see ZombieVisuals.zombie_texture()'s doc comment.
		var base_pos := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
		var spread := _crowd_spread_radius(display_count)
		for i in range(display_count):
			var variant := ((horde.id + i) % ZombieVisuals.VARIANT_COUNT + ZombieVisuals.VARIANT_COUNT) % ZombieVisuals.VARIANT_COUNT
			var variance := horde.individual_speed_variance(i)
			var offset := _scatter_offset(i, display_count, horde.id, spread, variance)
			# Transform2D(rotation, position) — rotation stays 0.0: which way
			# a figure faces is which of the 24 batch layers its transform
			# lands in (art baked into the texture), not a runtime rotation
			# of a single upright texture.
			per_layer[_zombie_batch_index(variant, horde_facing)].append(Transform2D(0.0, base_pos + offset))
		total_rendered += display_count

	for layer_index in range(_zombie_batch_layers.size()):
		var mm: MultiMesh = _zombie_batch_layers[layer_index].multimesh
		var transforms: Array = per_layer[layer_index]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform_2d(i, transforms[i])

## How far a HIGH-fidelity batched zombie crowd visually fans out — grows
## with sqrt(display_count) (area grows linearly with figure count) rather
## than staying pinned to FIGURE_SPREAD regardless of size, so a horde of
## hundreds reads as a bigger crowd instead of the same figures packed
## tighter into an unchanged circle. Anchored so a cluster around
## MEDIUM_ZOMBIE_CLUSTER_SIZE's own count matches FIGURE_SPREAD exactly — no
## visible jump right at the MEDIUM<->HIGH fidelity boundary.
func _crowd_spread_radius(display_count: int) -> float:
	return FIGURE_SPREAD * sqrt(maxf(1.0, float(display_count) / float(MEDIUM_ZOMBIE_CLUSTER_SIZE)))

## --- Facing (shared by units and hordes) ------------------------------------

## Derives an 8-way facing bucket from frame-to-frame world-position
## movement — there's no stored velocity/heading anywhere upstream
## (MovementStepper is stateless per-frame math, not an object holding
## per-unit state), so this reuses the position poll _update_unit_group()/
## _update_horde_group() already do every frame for their own positioning,
## rather than adding a new dependency to get at movement intent directly.
## `last_position`/`facing` are the caller's own tracking Dictionaries
## (_unit_* or _horde_*) — kept as plain Dictionary params rather than a
## stateful collaborator object since both call sites already own their
## dictionaries and the logic here is a single pure step, not enough
## behavior to justify a new class.
##
## New entities (no prior last_position) default to Facing8.S ("facing the
## camera") and count as unchanged on this first call, since there's no
## delta yet to compute a real facing from. Returns true only when the
## stored bucket actually changes, so callers can skip redraw work on an
## unchanged facing.
func _advance_facing(id: int, new_pos: Vector2, last_position: Dictionary, facing: Dictionary) -> bool:
	var previous_facing: GameEnums.Facing8 = facing.get(id, GameEnums.Facing8.S)
	var updated_facing := previous_facing
	if last_position.has(id):
		var delta: Vector2 = new_pos - last_position[id]
		if delta.length() >= MIN_FACING_MOVE_DISTANCE:
			updated_facing = FacingUtil.from_delta(delta)
	last_position[id] = new_pos
	facing[id] = updated_facing
	return updated_facing != previous_facing

## --- Shared figure drawing --------------------------------------------------

## Deterministic (index+group-seeded, not truly random) but not a perfect
## geometric ring — both angle and radius vary per figure via a cheap
## deterministic hash (_hash01()) rather than a clean division of the
## circle, and `group_seed` (caller passes the owning Horde/UnitInstance's
## own .id) means different groups scatter differently from each other too.
## `spread_radius` (default FIGURE_SPREAD) — _rebuild_zombie_batches() is
## the one caller that overrides it via _crowd_spread_radius(), so a large
## batched horde fans out over a bigger area instead of packing hundreds of
## figures into the same small circle a 5-figure MEDIUM cluster uses.
## `individual_variance` (default 1.0), read from
## Horde.individual_speed_variance(index) at the zombie call sites — a
## faster zombie (variance > 1.0) drifts further from the group's center, a
## slower one lags closer in, a visible correlation between a specific
## figure's persistent stat and where it's drawn.
func _scatter_offset(index: int, total: int, group_seed: int = 0, spread_radius: float = FIGURE_SPREAD, individual_variance: float = 1.0) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var base_angle := TAU * float(index) / float(total)
	var angle_jitter := (_hash01(index * 2 + group_seed * 7) - 0.5) * (TAU / float(total)) * 0.8  ## Up to ~80% of one slot's own angular width either way — enough to break perfect evenness without figures swapping places/overlapping.
	var radius_jitter := 0.6 + _hash01(index * 2 + 1 + group_seed * 7) * 0.7  ## 0.6x-1.3x spread_radius — near/far figures, not all on the same circle.
	var angle := base_angle + angle_jitter
	return Vector2(cos(angle), sin(angle)) * spread_radius * radius_jitter * individual_variance

## Cheap deterministic 0..1 pseudo-random value from an int seed — no
## RandomNumberGenerator instance needed for a single scalar, same approach
## LocalDetailGenerator's own coordinate-seeding (_hex_seed()) uses.
func _hash01(seed_value: int) -> float:
	var h := (seed_value * 2654435761) & 0x7FFFFFFF  ## Knuth's multiplicative hash constant, masked positive.
	return float(h % 10000) / 10000.0

func _build_figure(color: Color, radius: float, offset: Vector2) -> Node2D:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _circle_points(radius)
	shape.position = offset
	return shape

func _build_diamond(color: Color, radius: float) -> Node2D:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
	return shape

func _circle_points(radius: float, segments: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
