class_name TacticalEntityLayer
extends Node2D

## Design doc Phase 2.5.4: individual-figure rendering at Tactical zoom — a
## squad of UnitInstance.SQUAD_SIZE figures for Tier 0-3 units, one larger
## model for Tier 4-5 (the roster's named vehicles — "a squad of siege
## howitzers doesn't make sense the way a squad of Redcoats does"), and a
## capped cluster of individual zombie figures per Horde. This is the piece
## that was always missing from Tactical view: StrategicOverlayManager's own
## unit/horde markers (Phase 2.7.4/2.7.6) hide entirely while zoomed in
## (`visible = not is_tactical`), so before this class existed a unit or
## horde standing on a hex rendered as literally nothing the moment the
## camera crossed into Tactical zoom.
##
## Deliberately NOT gated on LocalDetailManager's hex-hydration set
## (settled/frontier-only, Phase 2.5.1) the way TacticalHexView's
## terrain/props/buildings are — a unit or horde crossing an otherwise-
## abstract wilderness hex still needs to be visible while the player is
## zoomed in looking straight at it, and gating on hydration would just
## reproduce the exact invisibility gap this class exists to close. Only
## camera zoom mode gates this layer; entities render at the same
## HexCoord.axial_to_world(hex_coord) + local_position world point props/
## buildings already use (Phase 2.5.3's local_position pattern, extended to
## UnitInstance/Horde by this phase). Read fresh every frame regardless of
## how that value is currently being written — continuous, real-time
## motion (MovementStepper, a later pass, user request) needed zero changes
## here as a result; this class was already "continuous-movement-ready".
##
## Squad headcount (UnitInstance.get_squad_headcount()) and zombie figure
## count are DERIVED, not separately tracked (design doc, decided) — no
## signal reliably covers every way current_hp/size can change (combat,
## Phase 2.5.4's own Garrison healing, Phase 5.9 casualty accumulation), so
## this class just re-polls UnitManager/HordeManager's live instance lists
## every frame while visible and diffs against what it drew last time,
## same "cheap self-healing full recompute" shape LocalDetailManager already
## uses for its own camera-driven neighborhood refresh — only redrawing a
## group's figures when its (headcount, fidelity) pair actually changed,
## not every frame.
##
## Parented as a WorldRoot sibling, same reasoning as every other Tactical-
## adjacent overlay (LocalDetailManager, StrategicOverlayManager,
## UnitCommandController): shares the same coordinate space, including
## whatever transform CameraController applies for the isometric toggle.
##
## **Rendering-at-scale, closed this pass (design doc Phase 5.10's own
## "~5,000-100,000... GPU-batched MultiMeshInstance2D" note):** HIGH-
## fidelity zombie figures — the only rendering path this project ever
## expected to reach that scale, per the design doc's own framing — now
## draw through ZombieVisuals.VARIANT_COUNT (3) shared MultiMeshInstance2D
## batch layers (_zombie_batch_layers, built once in _ready(),
## repopulated every frame by _rebuild_zombie_batches()) instead of one
## Polygon2D/Sprite2D scene node PER FIGURE. A MultiMesh instance is a
## transform written into a GPU buffer, not a scene-tree node the engine
## has to individually track/process/draw — the actual thing that made the
## old approach fall over well before real horde-scale counts, not the
## per-frame position math itself (that was always cheap). LOW/MEDIUM
## zombie rendering (a single blob, a small fixed cluster) and every unit
## figure (squads/vehicles/role markers) are UNCHANGED, still one node
## each — none of those come anywhere near the count where batching
## matters, so there's nothing to gain rewriting them too. See
## _rebuild_zombie_batches()'s own doc comment for the full mechanism,
## including the two-tier (per-horde + aggregate) render cap that replaces
## the old MAX_RENDERED_ZOMBIES below.
##
## **Phase 2.5.5 (Multi-Tier Visual Fidelity/LOD):** this class owns all
## three of Tactical zoom's internal fidelity bands (GameEnums.
## TacticalFidelity), driven by CameraController.tactical_fidelity_changed —
## HIGH is exactly the per-figure rendering this class already did before
## 2.5.5; LOW/MEDIUM are new, coarser bands as the camera sits closer to
## tactical_zoom_threshold. A fidelity change clears both headcount caches
## outright (their cached value now encodes fidelity too, via a Vector2i
## key) so every currently-tracked group redraws under the new band on the
## very next _process() poll — no per-group bookkeeping needed beyond that.
##
## **Phase 6.3.1 (real unit art, AI-generated per todo.md's decided plan):**
## `_build_unit_figure()`/`_build_role_marker()` both consult
## `UnitVisuals.unit_texture()` and draw a real sprite in place of the flat
## procedural shape wherever a PNG has been authored — HIGH and MEDIUM only.
## LOW deliberately stays the uniform per-category blob forever (see its
## own branch below) — it was never meant to distinguish unit types, only
## "unit vs. building vs. zombie", so there's no art gap to fill there. As
## of this pass no PNGs exist yet (see assets/units/README.md — no image
## generation tool is available in this Claude Code environment), so every
## unit still renders via the original procedural fallback; this is tested,
## ready infrastructure, not yet visible art.

const FIGURE_COLOR := Color(0.85, 0.8, 0.7)    ## Player-unit squad figures (HIGH) — pale "uniform" tone, distinct from terrain/prop/building colors.
const VEHICLE_COLOR := Color(0.5, 0.46, 0.32)  ## Tier 4-5 single-model units (HIGH) — a heavier, darker tone than a squad figure.
const ZOMBIE_COLOR := Color(0.33, 0.4, 0.27)   ## Sickly green-grey, distinct from both.

const FIGURE_RADIUS := 6.0
const VEHICLE_RADIUS := 16.0
const ZOMBIE_RADIUS := 5.0
const FIGURE_SPREAD := 20.0  ## How far individual squad/zombie figures scatter from their entity's own local_position.

## Performance safety net for the batched HIGH-fidelity zombie renderer
## (_rebuild_zombie_batches()) — two tiers, deliberately separate:
## MAX_RENDERED_ZOMBIES_PER_HORDE keeps one gigantic horde from
## single-handedly consuming the whole frame's render budget;
## MAX_TOTAL_RENDERED_ZOMBIES caps the AGGREGATE across every horde
## combined, the number that actually bounds GPU/CPU cost regardless of
## how the population happens to be split across however many Horde
## instances exist at once (merges/splits, Phase 5.10). A per-horde-only
## cap was already a latent unbounded-TOTAL gap in the pre-batch code (the
## old flat MAX_RENDERED_ZOMBIES applied independently per horde, times
## however many hordes existed) — closed here, not just carried forward.
## MAX_TOTAL_RENDERED_ZOMBIES is the design doc's own quoted LOW end
## (~5,000-100,000) — a flat cap, no frustum culling or spatial chunking
## yet, so it's a real starting point toward that range rather than the
## whole answer; worth revisiting toward the upper end if this ever stops
## being enough. LOW/MEDIUM's own much smaller fixed counts (a single blob,
## MEDIUM_ZOMBIE_CLUSTER_SIZE) are untouched by either cap.
const MAX_RENDERED_ZOMBIES_PER_HORDE := 1000
const MAX_TOTAL_RENDERED_ZOMBIES := 5000

## LOW fidelity (design doc: "simple silhouettes/blobs ... shape-and-color
## differentiated enough to tell unit from building from zombie") — one
## uniform blob per unit regardless of role/tier, one per horde regardless
## of size. Unit blob stays a circle (matches HIGH's own figure shape);
## the horde blob is deliberately a DIAMOND instead — the same shape
## StrategicOverlayManager's own horde marker already uses at Strategic
## zoom (2.7.6), so "unit vs zombie" reads by shape, not color alone, at
## the lowest Tactical fidelity too.
const LOW_UNIT_RADIUS := 10.0
const LOW_ZOMBIE_RADIUS := 10.0

## MEDIUM fidelity (design doc: "some discernible detail — enough to tell a
## unit's role or tier apart, not yet individual-figure detail") — one
## marker per unit, shaped by role (circle/triangle/diamond, the same
## "shape distinguishes, not just color" accessibility principle every
## other marker in this project already follows) and sized by tier. Hordes
## get a small FIXED-size cluster, deliberately not the true headcount —
## more detail than LOW's single blob, deliberately less than HIGH's full
## (capped) count.
const MEDIUM_UNIT_BASE_RADIUS := 7.0
const MEDIUM_UNIT_TIER_STEP := 1.5  ## Added per definition.tier, so a Tier 5 marker reads visibly larger than a Tier 0 one.
const MEDIUM_MELEE_COLOR := Color(0.72, 0.32, 0.28)   ## Rust red.
const MEDIUM_RANGED_COLOR := Color(0.35, 0.55, 0.78)  ## Blue.
const MEDIUM_SPECIAL_COLOR := Color(0.62, 0.5, 0.78)  ## Violet.
const MEDIUM_ZOMBIE_CLUSTER_SIZE := 5

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Optional — unset renders every horde regardless of vision, same "gracefully skip it" convention as every other optional dependency in this project.
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

## HIGH-fidelity zombie batch renderer — index == a ZombieVisuals variant
## (0..VARIANT_COUNT-1), built once in _ready(), repopulated every frame by
## _rebuild_zombie_batches(). See this class's own header doc comment and
## that function's for the full "why MultiMesh" reasoning.
var _zombie_batch_layers: Array[MultiMeshInstance2D] = []
## Dirty-check cache for _rebuild_zombie_batches() — see that function's
## own doc comment for why this exists and what it skips.
var _last_zombie_batch_signature: Array = []

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
		_zombie_batch_layers.append(_build_zombie_batch_layer(variant))

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_units()
	_refresh_hordes()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical

## Phase 2.5.5: a band change alone doesn't change the map's true headcount/
## size numbers, so the plain per-entity redraw-skip check below would never
## notice — clearing both caches forces every currently-tracked group to
## redraw under the new band next poll (see this class's own doc comment).
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

func _update_unit_group(instance: UnitInstance) -> void:
	var group: Node2D = _unit_groups[instance.id]
	group.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position

	var headcount := instance.get_squad_headcount()
	var draw_key := Vector2i(headcount, _fidelity)
	if _unit_draw_keys.get(instance.id, Vector2i(-1, -1)) == draw_key:
		return
	_unit_draw_keys[instance.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if headcount <= 0:
		return  # Destroyed this frame, about to be removed via unit_removed — draw nothing rather than a stale figure.

	match _fidelity:
		GameEnums.TacticalFidelity.LOW:
			# Deliberately NOT UnitVisuals-aware, even where art exists —
			# LOW is a uniform per-category blob by design (design doc:
			# "tell unit from building from zombie", not unit-from-unit),
			# see this class's own doc comment.
			group.add_child(_build_figure(FIGURE_COLOR, LOW_UNIT_RADIUS, Vector2.ZERO))
		GameEnums.TacticalFidelity.MEDIUM:
			group.add_child(_build_role_marker(instance))
		_:  # HIGH — unchanged from before 2.5.5, now UnitVisuals-aware (Phase 6.3.1).
			if instance.is_squad_rendered():
				for i in range(headcount):
					group.add_child(_build_unit_figure(instance, FIGURE_RADIUS, _scatter_offset(i, headcount, instance.id), FIGURE_COLOR))
			else:
				group.add_child(_build_unit_figure(instance, VEHICLE_RADIUS, Vector2.ZERO, VEHICLE_COLOR))

## Phase 6.3.1: real per-unit-type sprite art (UnitVisuals.unit_texture())
## in place of the flat circle where authored, sized to the same diameter
## the fallback circle would have used so real art slots into the existing
## squad-ring/vehicle sizing with no other layout change. Falls back to
## _build_figure()'s flat circle for any type with no PNG authored yet —
## same "art lands incrementally, zero code changes elsewhere" contract
## BuildingVisuals/TerrainVisuals already established. Uses Sprite2D rather
## than TacticalHexView's Polygon2D-quad-with-explicit-uv approach — there's
## no pre-existing polygon shape to texture here (figures are built ad hoc,
## not drawn onto an existing box), so a plain sprite scaled to the target
## diameter is the simpler, equally-correct choice for a standalone image.
func _build_unit_figure(instance: UnitInstance, radius: float, offset: Vector2, fallback_color: Color) -> Node2D:
	var texture := UnitVisuals.unit_texture(instance.definition.unit_type)
	if not texture:
		return _build_figure(fallback_color, radius, offset)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = offset
	var largest_dim := maxf(texture.get_width(), texture.get_height())
	sprite.scale = Vector2.ONE * ((radius * 2.0) / largest_dim)
	return sprite

## MEDIUM fidelity's "tell a unit's role or tier apart" marker. Real art
## (Phase 6.3.1), when authored, replaces the procedural shape here too —
## the SAME texture HIGH fidelity uses, just scaled to this tier's smaller
## radius rather than a separately-generated MEDIUM-specific asset (todo.md
## Phase 6.3.2's own decision: one generated image per unit, reused at both
## fidelity bands, not a per-band asset set). Falls back to the original
## shape-by-role marker (never color alone, same accessibility principle
## every other marker in this project follows) when no art exists yet.
func _build_role_marker(instance: UnitInstance) -> Node2D:
	var radius := MEDIUM_UNIT_BASE_RADIUS + float(instance.definition.tier) * MEDIUM_UNIT_TIER_STEP
	var texture := UnitVisuals.unit_texture(instance.definition.unit_type)
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
## diameter approach _build_unit_figure() already uses, in place of the flat
## circle where authored — falls back to it individually per figure, same
## "art lands incrementally" contract. `horde_id + index` seeds which of
## ZombieVisuals.VARIANT_COUNT looks this specific figure gets — deterministic
## (same figure always looks the same across redraws) but varied across a
## horde's own figures so a cluster doesn't read as identical clones.
func _build_zombie_figure(horde_id: int, index: int, offset: Vector2) -> Node2D:
	var texture := ZombieVisuals.zombie_texture(horde_id + index)
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
	# Once per frame, not once per horde — see this function's own doc
	# comment for why HIGH-fidelity figures don't live under each horde's
	# own `group` node the way LOW/MEDIUM's do.
	_rebuild_zombie_batches()

## Individual zombie figures are live-vision intel, not remembered-terrain
## intel — gated on VISIBLE (Fog of War, Phase 2.6), a strictly stricter bar
## than TacticalHexView's own at-least-EXPLORED requirement for terrain and
## buildings, matching the Strategic spotted-horde-marker's own "ghost once
## vision is lost" philosophy (Phase 2.7.6) rather than that class's
## specific ghost-rendering mechanism.
func _update_horde_group(horde: Horde) -> void:
	var group: Node2D = _horde_groups[horde.id]
	group.position = HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	group.visible = _fog_of_war_manager == null or _fog_of_war_manager.is_visible(horde.hex_coord)

	var display_count := _horde_display_count(horde.size)
	var draw_key := Vector2i(display_count, _fidelity)
	if _horde_draw_keys.get(horde.id, Vector2i(-1, -1)) == draw_key:
		return
	_horde_draw_keys[horde.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if display_count <= 0:
		return

	if _fidelity == GameEnums.TacticalFidelity.LOW:
		# Deliberately NOT ZombieVisuals-aware, even where art exists — same
		# "LOW is a uniform per-category blob by design" call this class
		# already makes for units (see _update_unit_group()'s own doc comment).
		group.add_child(_build_diamond(ZOMBIE_COLOR, LOW_ZOMBIE_RADIUS))
	elif _fidelity == GameEnums.TacticalFidelity.MEDIUM:
		for i in range(display_count):
			var variance := horde.individual_speed_variance(i)
			group.add_child(_build_zombie_figure(horde.id, i, _scatter_offset(i, display_count, horde.id, FIGURE_SPREAD, variance)))
	# else HIGH: rendered through the shared MultiMesh batch layers instead
	# of per-horde child nodes — see _rebuild_zombie_batches() (called once
	# per frame from _refresh_hordes(), not per horde) and this class's own
	# header doc comment. Nothing to add here; the clear above already
	# removed any stale LOW/MEDIUM children left over from a fidelity
	# change, and `group` itself still exists purely to carry this horde's
	# position/fog-visibility for bookkeeping (_horde_groups' own lifecycle).

## How many individual zombie figures to actually draw for a horde of
## `size` — LOW collapses to a single blob (display_count itself doesn't
## matter beyond ">0", the LOW branch above always draws exactly one
## diamond), MEDIUM shows a small fixed cluster regardless of true size
## (more detail than LOW, deliberately less than the real count), HIGH
## shows the real (capped) count, unchanged from before 2.5.5.
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

## --- GPU-batched HIGH-fidelity zombie rendering (Phase 5.10) ---------------

## One shared MultiMeshInstance2D per ZombieVisuals art variant — a single
## draw call renders every figure using that variant, across EVERY horde on
## the map at once, regardless of count. No texture authored for a variant
## falls back to a solid `modulate` tint (ZOMBIE_COLOR) instead — a
## MultiMesh has no per-instance shape choice the way a lone Polygon2D
## circle does, so a flat-tinted quad is the closest equivalent to
## `_build_figure()`'s own flat-color fallback, not a perfect match.
##
## **Real bug found and fixed (adversarial review): `mesh.size` used to be
## a fixed square (`ZOMBIE_RADIUS * 2.0` on both axes), unlike every OTHER
## texture consumer in this file** (`_build_unit_figure()`/
## `_build_role_marker()`/`_build_zombie_figure()` — the exact same art
## this function draws at MEDIUM fidelity — all explicitly scale by
## `largest_dim := maxf(width, height)` to preserve aspect ratio). A
## `QuadMesh`'s UVs span its own fixed `size` regardless of the texture's
## real pixel dimensions — painting a non-square texture across a square
## quad stretches it. Currently inert (every shipped `zombie_%d.png` is a
## real 2048x2048 square, and `assets/zombies/README.md`'s own prompt
## template mandates "Square aspect ratio (1:1)" for every past AND future
## asset in this category) but a code-level gap, not something the art
## pipeline's own convention should have to silently keep bailing out.
## Fixed the same way the aspect-preserving siblings do it: size each
## layer's own quad from ITS OWN texture's real dimensions (not a shared
## flat constant), scaled so the longer axis lands on the same
## `ZOMBIE_RADIUS * 2.0` diameter every other rendering path already uses.
func _build_zombie_batch_layer(variant: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
	mm.use_custom_data = false

	var texture := ZombieVisuals.zombie_texture(variant)
	var mesh := QuadMesh.new()
	if texture:
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		mesh.size = Vector2(texture.get_width(), texture.get_height()) * ((ZOMBIE_RADIUS * 2.0) / largest_dim)
	else:
		mesh.size = Vector2.ONE * (ZOMBIE_RADIUS * 2.0)  ## No art to derive real dimensions from — same square fallback the flat-color case always implied.
	mm.mesh = mesh
	mm.instance_count = 0

	var mmi := MultiMeshInstance2D.new()
	mmi.name = "ZombieBatch%d" % variant
	mmi.multimesh = mm
	if texture:
		mmi.texture = texture
	else:
		mmi.modulate = ZOMBIE_COLOR
	# Self-contained z_index (scoped to THIS node's own children only, not
	# the whole scene the way LocalDetailManager's own TacticalWallLayer
	# fix explicitly had to avoid — see that fix's own doc comment on why a
	# z_index there would have leaked into cross-file ordering. Here every
	# competing node — unit/horde groups included — is also a direct child
	# of this same TacticalEntityLayer, so z_index only ever arbitrates
	# among them, nothing else) — deliberately puts the horde ABOVE units:
	# real bug found (adversarial review) — these 3 layers used to be
	# created here in _ready(), unconditionally the first 3 children, while
	# every unit/horde group node is only ever added later from
	# _refresh_units()/_refresh_hordes() (both _process()-driven, always
	# after _ready()). With z_index untouched, Godot draws lower child
	# index first — a hard, PERMANENT "zombies always render under units"
	# invariant, not the old per-node code's spawn-order-dependent (i.e.
	# arbitrary either way) layering. At the exact moment this matters most
	# — a squad in melee with a horde — that permanently buried the zombie
	# figures being fought under the unit sprites. A defensive "hold the
	# light" game is about seeing the threat clearly; z_index = 1 makes
	# that a deliberate, documented choice instead of an accidental one.
	mmi.z_index = 1
	add_child(mmi)
	return mmi

## Repopulates every _zombie_batch_layers entry — hordes move continuously
## in general, so every visible figure's transform needs rewriting when
## anything actually changes; MultiMesh transform writes are exactly the
## cheap, GPU-side operation this whole approach exists to lean on instead
## of the engine individually processing/drawing one scene node per figure.
## Zeroes every layer's `instance_count` outright (not just skipping the
## rebuild) when not at HIGH fidelity or with no HordeManager wired, so a
## fidelity drop mid-frame can't leave a stale batch rendered underneath
## LOW/MEDIUM's own per-node figures — and invalidates the dirty-check
## signature below so the NEXT HIGH frame always does a real rebuild rather
## than wrongly concluding "nothing changed" against a multimesh this same
## branch just zeroed out.
##
## **Real gap found and fixed (adversarial review): this used to
## unconditionally recompute every figure's scatter offset (hash + sin/cos)
## and re-upload every transform, every single frame, for every horde** —
## with no equivalent to the _horde_draw_keys/_unit_draw_keys cache that
## gates literally every OTHER rendering path in this file. That's the
## right call for a horde that's actually moving, but two real HordeManager
## states leave `hex_coord`/`local_position` completely frozen for extended
## stretches: `stun_seconds_remaining > 0` (Dragoon knockback) and
## ATTACKING an unbreached wall (a siege can grind on for many ticks while
## the wall's HP drains — see HordeManager._advance_horde()'s own two
## early-return branches). A horde pinned against a wall is exactly the
## large-and-near-the-player case this whole pass targets, reliably inside
## Fog-of-War vision (so never excluded from the render budget) — it used
## to pay a full per-figure trig/hash recompute every frame for the entire
## siege despite not one figure's position actually changing.
##
## Fix: a per-frame signature — (id, hex_coord, local_position, size,
## fog-visibility) per horde, same order `get_all_hordes()` already
## returns — compared against last frame's via a plain Array `==` (GDScript
## Arrays compare by value/content, not reference, including nested
## Vector2i/Vector2 elements). O(hordes) to build and compare, not
## O(total figures) — cheap even when it DOES differ and a real rebuild has
## to run anyway, and strictly cheaper than the trig-heavy work it might
## skip. When it matches, this returns having touched NOTHING — Godot's
## MultiMesh instance buffers persist on the GPU side across frames on
## their own; there is nothing to "keep displaying the same thing", the
## previous frame's write is still there untouched.
##
## Same `horde_id + index` variant-assignment formula _build_zombie_figure()
## already uses (wrapped mod VARIANT_COUNT here since ZombieVisuals.
## zombie_texture() normally does that wrapping itself but this function
## needs the variant INDEX up front, before calling it, to know which
## layer's transform list to append to) — a figure that happens to render
## via both paths across a fidelity change looks identical either way, not
## a jarring re-randomization.
##
## Two render caps applied together, both documented on their own
## constants above: MAX_RENDERED_ZOMBIES_PER_HORDE first (per horde, so one
## giant horde can't eat the whole budget), then whatever room remains
## under MAX_TOTAL_RENDERED_ZOMBIES (the real aggregate ceiling). Hordes
## are iterated in HordeManager.get_all_hordes() order — deterministic
## WITHIN a frame, but not priority-sorted by e.g. proximity to the camera;
## once the aggregate cap is hit, remaining hordes simply render nothing
## this frame rather than an arbitrary/unfair pick — an accepted, disclosed
## simplification, not a fairness guarantee. **Disclosed, not solved this
## pass (adversarial review): this extends across frames too** — a merge
## growing an earlier-in-the-array horde, or a split/casualty-spawn
## appending a new one, can shift how much of the fixed budget a
## completely different, unmoved horde gets from one frame to the next,
## since allocation is greedy-first-come over the live array rather than
## stable/sorted. Only reachable once total zombie population genuinely
## exceeds MAX_TOTAL_RENDERED_ZOMBIES (today's real starting economy —
## STARTING_HORDE_COUNT=3 at 10-25 each, no ramp-up curve yet, see
## HordeManager's own header doc comment — makes that unlikely in current
## gameplay, though it's exactly the scale this pass is explicitly building
## toward). A real fix (stable sort by some priority, or proportional
## scaling instead of greedy cutoff) is a reasonable future step, not
## attempted here.
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
		signature.append([horde.id, horde.hex_coord, horde.local_position, horde.size, visible])
	if signature == _last_zombie_batch_signature:
		return
	_last_zombie_batch_signature = signature

	var per_variant: Array = []  # Array[Array[Transform2D]], index == variant
	for _v in range(ZombieVisuals.VARIANT_COUNT):
		per_variant.append([])

	var total_rendered := 0
	for horde in hordes:
		if total_rendered >= MAX_TOTAL_RENDERED_ZOMBIES:
			break
		if _fog_of_war_manager and not _fog_of_war_manager.is_visible(horde.hex_coord):
			continue  # Same live-vision gate _update_horde_group()'s own group.visible already applies for LOW/MEDIUM.
		var display_count := mini(horde.size, MAX_RENDERED_ZOMBIES_PER_HORDE)
		display_count = mini(display_count, MAX_TOTAL_RENDERED_ZOMBIES - total_rendered)
		if display_count <= 0:
			continue
		var base_pos := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
		var spread := _crowd_spread_radius(display_count)
		for i in range(display_count):
			var variant := ((horde.id + i) % ZombieVisuals.VARIANT_COUNT + ZombieVisuals.VARIANT_COUNT) % ZombieVisuals.VARIANT_COUNT
			var variance := horde.individual_speed_variance(i)
			var offset := _scatter_offset(i, display_count, horde.id, spread, variance)
			# Transform2D(rotation, position) — rotation deliberately stays 0.0
			# regardless of variance/offset (user request: zombies must stay
			# upright and never rotate, confirmed already true elsewhere in
			# this file before this pass; this batched path is the one place
			# that could have silently violated it by deriving a rotation
			# from movement/offset direction, so it's called out explicitly).
			per_variant[variant].append(Transform2D(0.0, base_pos + offset))
		total_rendered += display_count

	for v in range(ZombieVisuals.VARIANT_COUNT):
		var mm: MultiMesh = _zombie_batch_layers[v].multimesh
		var transforms: Array = per_variant[v]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform_2d(i, transforms[i])

## How far a HIGH-fidelity batched zombie crowd visually fans out — grows
## with sqrt(display_count) (area grows linearly with figure count, a
## standard crowd-density heuristic) rather than staying pinned to
## FIGURE_SPREAD regardless of size, so a horde of hundreds actually reads
## as a bigger crowd on screen instead of the same figures just packed
## tighter into an unchanged circle. Anchored so a cluster around
## MEDIUM_ZOMBIE_CLUSTER_SIZE's own count matches FIGURE_SPREAD exactly —
## no visible jump right at the MEDIUM<->HIGH fidelity boundary for a horde
## small enough that HIGH's own (otherwise-uncapped) real headcount happens
## to land near that size anyway. A placeholder tuning curve, not an
## architecture decision, same framing as every other constant table here.
func _crowd_spread_radius(display_count: int) -> float:
	return FIGURE_SPREAD * sqrt(maxf(1.0, float(display_count) / float(MEDIUM_ZOMBIE_CLUSTER_SIZE)))

## --- Shared figure drawing --------------------------------------------------

## Deterministic (index+group-seeded, not truly random — same figure count
## for the same entity always scatters into the same shape, no per-frame
## jitter) — but no longer a perfect geometric ring. **Real bug fixed
## (player report: zombies/units "move to the center of a hex tile and
## then rotate around it in a very programmatic way" — a perfectly
## evenly-spaced ring, `TAU * index/total`, reads as synthetic regardless
## of how organically the group itself moves, and EVERY squad/horde on the
## map shared the exact same shape).** Both angle and radius now vary per
## figure via a cheap deterministic hash (`_hash01()`) rather than a clean
## division of the circle, and `group_seed` (caller passes the owning
## Horde/UnitInstance's own `.id`) means different groups scatter
## differently from each other too, not just look non-circular each.
## Still spreads figures out for legibility — same underlying purpose
## `TacticalHexView._resolved_building_position()` already serves for
## multiple buildings sharing one hex — just organically now instead of
## geometrically.
## `spread_radius` (default FIGURE_SPREAD, every pre-existing call site's
## own unchanged behavior) — _rebuild_zombie_batches() is the one caller
## that overrides it, via _crowd_spread_radius(), so a large batched horde
## visually fans out over a bigger area instead of packing hundreds of
## figures into the same small circle a 5-figure MEDIUM cluster uses.
## `individual_variance` (default 1.0, every pre-existing call site's own
## unchanged behavior) — real per-zombie identity (user request:
## "individual zombies... rng based positioning, movement, speed"), read
## from Horde.individual_speed_variance(index) at the zombie call sites
## below rather than invented fresh here. A faster zombie (variance > 1.0)
## drifts further out from the group's own center — reads as eager/
## out-front — a slower one (variance < 1.0) lags closer in, a real
## visible correlation between a specific figure's persistent stat and
## where it's actually drawn, not just cosmetic noise on top of it.
func _scatter_offset(index: int, total: int, group_seed: int = 0, spread_radius: float = FIGURE_SPREAD, individual_variance: float = 1.0) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var base_angle := TAU * float(index) / float(total)
	var angle_jitter := (_hash01(index * 2 + group_seed * 7) - 0.5) * (TAU / float(total)) * 0.8  ## Up to ~80% of one slot's own angular width either way — enough to break the perfect evenness without figures swapping places/overlapping.
	var radius_jitter := 0.6 + _hash01(index * 2 + 1 + group_seed * 7) * 0.7  ## 0.6x-1.3x spread_radius — an organic scatter has near/far figures, not every one sitting on the exact same circle.
	var angle := base_angle + angle_jitter
	return Vector2(cos(angle), sin(angle)) * spread_radius * radius_jitter * individual_variance

## Cheap deterministic 0..1 pseudo-random value from an int seed — no
## RandomNumberGenerator instance needed for a single scalar, same
## "small enough to just hash" reasoning LocalDetailGenerator's own
## coordinate-seeding (_hex_seed()) already applies elsewhere.
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
