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
## **Rendering at scale:** HIGH-fidelity zombies are not this class's own
## figures at all any more — they are ZombieSwarmManager's crowds
## (design_doc.md §2.1), and this class draws each ZombieSwarm through one
## pooled MultiMeshInstance2D. A MultiMesh instance is a transform in a GPU
## buffer, not a scene-tree node the engine individually tracks, processes
## and draws; that per-node overhead, not the position math, is what made
## one node per figure fall over before real horde-scale counts. See
## _refresh_swarm_batches() for what changed and why it is not just a
## refactor. LOW/MEDIUM zombie rendering and every unit figure are
## unchanged, still one node each — none come near the count where batching
## matters.
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

## The two render caps that used to live here (1,000 figures per horde,
## 5,000 across the map) are gone: what may be drawn is now what was
## instantiated, and ZombieSwarmManager.ENTITY_BUDGET bounds that from a
## measurement rather than from an assumption. LOW/MEDIUM's own small fixed
## counts never went through either cap.

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
@export var zombie_swarm_manager_path: NodePath  ## Optional — §2.1's tactical layer. Unset makes HIGH fidelity render as MEDIUM (a five-figure cluster per horde) instead of real individuals.

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController
var _zombie_swarm_manager: ZombieSwarmManager

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

## HIGH-fidelity zombie renderer — one pooled MultiMeshInstance2D per live
## ZombieSwarm, index-aligned with ZombieSwarmManager.get_swarms(). The key
## array caches each layer's last-applied (lane, facing) so texture and quad
## size are only rewritten when they actually change; the transform buffer is
## rewritten every frame, straight from the simulation's own array.
var _swarm_layers: Array[MultiMeshInstance2D] = []
var _swarm_layer_keys: Array[Vector2i] = []

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

	if zombie_swarm_manager_path != NodePath():
		_zombie_swarm_manager = get_node(zombie_swarm_manager_path)
	# A lane IS a texture variant to this renderer; the two constants live in
	# different classes on purpose (a data class should not import a visuals
	# one) so the agreement is asserted here rather than assumed.
	if ZombieSwarm.LANE_COUNT != ZombieVisuals.VARIANT_COUNT:
		push_error("ZombieSwarm.LANE_COUNT (%d) must equal ZombieVisuals.VARIANT_COUNT (%d)."
				% [ZombieSwarm.LANE_COUNT, ZombieVisuals.VARIANT_COUNT])

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
	# Once per frame, not once per horde — HIGH-fidelity figures belong to
	# ZombieSwarmManager's crowds, not to any one horde's `group` node.
	_refresh_swarm_batches()

## Individual zombie figures are live-vision intel, not remembered-terrain
## intel — gated on VISIBLE (Fog of War), a stricter bar than
## TacticalHexView's own at-least-EXPLORED requirement for terrain and
## buildings, matching the Strategic spotted-horde-marker's own "ghost once
## vision is lost" philosophy.
func _update_horde_group(horde: Horde) -> void:
	var group: Node2D = _horde_groups[horde.id]
	group.position = HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	group.visible = _fog_of_war_manager == null or _fog_of_war_manager.is_visible(horde.hex_coord)

	# Kept even though HIGH no longer reads it: MEDIUM's per-figure sprites
	# need a facing, and this is the one place every fidelity band visits per
	# horde per frame. HIGH's facing belongs to the swarm and is derived from
	# the crowd's own anchor movement (ZombieSwarmManager._update_group_shape).
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
	# else HIGH with a simulation wired: display_count is 0, so nothing is
	# added here. The horde's individuals are ZombieSwarmManager's crowd,
	# drawn by _refresh_swarm_batches(); the clear above already removed any
	# stale LOW/MEDIUM children left by a fidelity change, and `group` still
	# exists to carry this horde's position and fog visibility.

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
			# The swarm owns HIGH's individuals; a horde's group node only
			# carries its position and fog visibility. With no simulation
			# wired there is nothing to own them, so HIGH borrows MEDIUM's
			# cluster rather than rendering an invisible horde.
			return 0 if _zombie_swarm_manager else mini(size, MEDIUM_ZOMBIE_CLUSTER_SIZE)

## --- GPU-batched HIGH-fidelity zombie rendering -----------------------------

## One MultiMeshInstance2D per live ZombieSwarm, pooled and reused. Each swarm
## is already (one hex, one source, one art variant) with a single whole-crowd
## facing, so it resolves to exactly one texture — which is the constraint a
## MultiMesh imposes, and the reason the tactical layer is divided into
## ZombieSwarm.LANE_COUNT lanes in the first place.
##
## **This replaced a per-horde scatter renderer, and the change is not
## cosmetic.** The old path derived every figure's position from a hash of
## (horde id, index) around the horde's own point, so a "crowd" was a
## decoration: it could not be walked through, could not lag behind its horde,
## and had no positions to save. It also capped at 5,000 figures globally and
## rewrote every transform through MultiMesh.set_instance_transform_2d(), one
## engine call per figure. This path assigns MultiMesh.buffer in a single bulk
## copy from the array the simulation already writes into (see ZombieSwarm's
## own doc comment), so the cap is now ZombieSwarmManager.ENTITY_BUDGET —
## 60,000, measured, rather than 5,000 assumed.
##
## LOW and MEDIUM are untouched: both are coarse bands near
## tactical_zoom_threshold where a blob or a five-figure cluster is the point,
## and neither has ever needed the swarm.
##
## With no ZombieSwarmManager wired, HIGH renders as MEDIUM (see
## _horde_display_count()) rather than as nothing. That is a real
## configuration — a test scene instantiating this layer without the
## simulation — not dead code.
func _refresh_swarm_batches() -> void:
	if _fidelity != GameEnums.TacticalFidelity.HIGH or not _zombie_swarm_manager:
		for layer in _swarm_layers:
			layer.visible = false
		return

	var swarms := _zombie_swarm_manager.get_swarms()
	for i in swarms.size():
		var swarm: ZombieSwarm = swarms[i]
		var layer := _swarm_layer(i)
		var count := swarm.size()
		# Same live-vision gate _update_horde_group() applies for LOW/MEDIUM:
		# individual zombies are intel, not remembered terrain.
		var shown := count > 0 and (_fog_of_war_manager == null or _fog_of_war_manager.is_visible(swarm.hex_coord))
		layer.visible = shown
		if not shown:
			continue
		_apply_swarm_look(layer, i, swarm)
		var mm := layer.multimesh
		if mm.instance_count != count:
			mm.instance_count = count  ## Reallocates and clears, so the buffer assignment below has to follow it.
		mm.buffer = swarm.buffer()
		# Without this the crowd is invisible, and it took a screenshot to
		# find out: a MultiMeshInstance2D culls against its MultiMesh's AABB,
		# and assigning MultiMesh.buffer does not recompute one. Every
		# instance therefore still measured as the identity transform left by
		# `instance_count =`, i.e. a 10x10 box at the world origin — while the
		# real crowd stood 120,000 world units away, off the item's own rect,
		# and was culled entirely. Nothing in the data was wrong; 60,000
		# zombies simply never reached the screen.
		var reach := swarm.spread * ZombieSwarm.SNAP_SPREAD_MULTIPLE + ZOMBIE_RADIUS
		mm.custom_aabb = AABB(
			Vector3(swarm.anchor.x - reach, swarm.anchor.y - reach, -1.0),
			Vector3(reach * 2.0, reach * 2.0, 2.0))

	for i in range(swarms.size(), _swarm_layers.size()):
		_swarm_layers[i].visible = false


## Grows the pool on demand. Layers are never freed — the count tracks the
## live-hex set, which ZombieSwarmManager's own allocation already bounds, and
## churning scene nodes as the player pans is exactly the per-node cost this
## renderer exists to avoid.
func _swarm_layer(index: int) -> MultiMeshInstance2D:
	while _swarm_layers.size() <= index:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = false
		mm.use_custom_data = false
		mm.mesh = QuadMesh.new()
		mm.instance_count = 0

		var mmi := MultiMeshInstance2D.new()
		mmi.name = "ZombieSwarm%d" % _swarm_layers.size()
		mmi.multimesh = mm
		# z_index is scoped to this node's own children (every competing node —
		# unit and horde groups included — is also a direct child of this same
		# layer). Puts zombies ABOVE units deliberately: without it Godot draws
		# by child index, and these nodes are created lazily from _process(),
		# so a crowd would be buried under unit sprites at the exact moment
		# (melee contact) that seeing the threat matters most.
		mmi.z_index = 1
		add_child(mmi)
		_swarm_layers.append(mmi)
		_swarm_layer_keys.append(Vector2i(-1, -1))
	return _swarm_layers[index]


## Texture and quad size for a layer, rewritten only when the swarm occupying
## it changes lane or facing. A crowd changes facing when its anchor turns,
## which is rare; its buffer changes every frame, which is why the two are
## separated.
##
## The quad is sized from the texture's real dimensions, scaled so its longer
## axis lands on the same ZOMBIE_RADIUS * 2.0 diameter every other rendering
## path uses — a QuadMesh's UVs span its own `size` regardless of the
## texture's pixel dimensions, so a fixed square would stretch non-square art.
func _apply_swarm_look(layer: MultiMeshInstance2D, index: int, swarm: ZombieSwarm) -> void:
	var key := Vector2i(swarm.lane, swarm.facing)
	if _swarm_layer_keys[index] == key:
		return
	_swarm_layer_keys[index] = key

	var texture := ZombieVisuals.zombie_texture(swarm.lane, swarm.facing)
	var mesh: QuadMesh = layer.multimesh.mesh
	if texture:
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		mesh.size = Vector2(texture.get_width(), texture.get_height()) * ((ZOMBIE_RADIUS * 2.0) / largest_dim)
		layer.texture = texture
		layer.modulate = Color.WHITE
	else:
		mesh.size = Vector2.ONE * (ZOMBIE_RADIUS * 2.0)  ## No art to derive real dimensions from — same square fallback the flat-color case implies.
		layer.texture = null
		layer.modulate = ZOMBIE_COLOR  ## A MultiMesh has no per-instance shape the way a lone Polygon2D circle does.

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
## `spread_radius` defaults to FIGURE_SPREAD and no caller overrides it any
## more — the HIGH-fidelity path that did now gets its fan-out from
## ZombieSwarmManager._horde_spread(), which applies the same sqrt growth to
## a real crowd instead of to a scatter pattern.
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
