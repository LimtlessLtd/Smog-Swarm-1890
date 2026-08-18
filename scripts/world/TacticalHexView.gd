class_name TacticalHexView
extends Node2D

## Close-zoom detail for one hex (Tactical view). Composes a scatter of
## placeholder props and every BuildingInstance in this hex rendered at its
## own precise position, instead of one flat tile standing in for the whole
## ~5x5 mile area. Draws NO ground of its own — TerrainMeshView owns the
## ground for the whole world, not per hex, and HexGridMap's flat tile shows
## through wherever no mesh chunk is baked.
## Spawned/freed by LocalDetailManager as the camera crosses the tactical
## zoom threshold and pans between hexes; only exists for a hex that has
## qualified as settled/frontier.
##
## `fidelity` affects props AND buildings, MEDIUM/HIGH treated identically
## for both (no MEDIUM-vs-HIGH distinction the way TacticalEntityLayer has
## for units) — at LOW, props collapse to one uniform blob shape per prop
## type, and buildings skip their real 2048x2048 sprite in favor of the
## same BuildingVisuals.category_color() flat-box fallback an unauthored
## building type already uses (extended from "no art exists" to "art
## exists but this fidelity band doesn't want it" — one existing fallback
## covers both). Buildings also skip their smoke/fire particle effects at
## LOW (BuildingEffectsVisuals — real per-frame CPU particle sims, cut
## exactly where the most buildings are likely on screen at once); the
## pulsing light glow stays at every fidelity, it's GPU-shader-only with no
## per-frame simulation cost. set_fidelity() only rebuilds THESE two things
## (_rebuild_fidelity_dependent()) — the grid outline and the ZoC overlay
## never change with fidelity and used to get needlessly torn down and rebuilt
## on every LOW<->MEDIUM<->HIGH crossing anyway.

var cell: HexCell
var _props: Array[PropInstance] = []
var _buildings: Array[BuildingInstance] = []
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH
var _zoc_state: ZoneOfControlState
var _building_containers: Dictionary = {}  # int (BuildingInstance.id) -> Node2D — rebuilt every _rebuild_fidelity_dependent(), lets set_building_selected() re-tint one building in place.
var _props_layer: Node2D  ## Created once in _redraw(); _rebuild_fidelity_dependent() only clears/repopulates ITS children, leaving this node's own position among TacticalHexView's children (and therefore draw order) untouched.
var _buildings_layer: Node2D  ## Same shape as _props_layer, for buildings.
var _selected_building: BuildingInstance  ## Threaded through setup() so a hex that dehydrates and rehydrates while its own building stays selected redraws already knowing to highlight it.

func _ready() -> void:
	position = HexCoord.axial_to_world(cell.coord)
	DisplaySettings.changed.connect(_on_display_settings_changed)
	if cell:
		_redraw()

## Call before this node enters the tree; mirrors HexCellView.setup()'s
## defer-to-_ready() pattern since child nodes don't exist until _ready() runs.
## `fog_state` defaults to VISIBLE: LocalDetailManager only ever hydrates a
## hex that's at least EXPLORED, so the only two values that arrive here are
## EXPLORED (dimmed) and VISIBLE (full color). `zoc_state` defaults to null,
## meaning "no LogisticsNetwork wired". `selected_building` defaults to
## null, meaning nothing of this hex's is currently selected —
## LocalDetailManager passes its live value in on every hydrate.
func setup(p_cell: HexCell, props: Array[PropInstance], buildings: Array[BuildingInstance], fog_state: GameEnums.FogState = GameEnums.FogState.VISIBLE, fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH, zoc_state: ZoneOfControlState = null, selected_building: BuildingInstance = null) -> void:
	cell = p_cell
	_props = props
	_buildings = buildings
	_fidelity = fidelity
	_zoc_state = zoc_state
	_selected_building = selected_building
	set_fog_state(fog_state)
	if is_inside_tree():
		_redraw()

## Pushed live by LocalDetailManager whenever LogisticsNetwork recomputes —
## mirrors set_fidelity()'s "update in place, only redraw if it changed" shape.
func set_zoc_state(zoc_state: ZoneOfControlState) -> void:
	_zoc_state = zoc_state
	if is_inside_tree():
		_update_zoc_overlay()

func _on_display_settings_changed() -> void:
	_update_zoc_overlay()

## Re-tints just the one matching container in place, same "update in
## place, no full redraw" shape set_fog_state()/set_fidelity() follow.
## `instance` is always one of THIS hex's own buildings in practice
## (LocalDetailManager looks the owning hex up via BuildingInstance.hex_coord
## first); the lookup is a no-op rather than an error otherwise.
func set_building_selected(instance: BuildingInstance, is_selected: bool) -> void:
	if not instance:
		return
	if is_selected:
		_selected_building = instance
	elif _selected_building and _selected_building.id == instance.id:
		_selected_building = null
	var container: Node2D = _building_containers.get(instance.id)
	if container:
		var base := _building_base_modulate(instance)
		container.modulate = _SELECTED_TINT * base if is_selected else base

## Dims this hex's ENTITIES — props and buildings — so a remembered-but-not-
## currently-visible hex reads as one dimmed scene. It no longer dims terrain,
## because this node no longer draws any: TerrainMeshView owns that, and
## HexCellView's overlay (lifted to FogVisuals.TERRAIN_OVERLAY_Z_INDEX) fogs it.
## modulate still reaches the entities because they sit at z_index 0 and above,
## which is over that overlay's band rather than under it.
##
## This node used to add a second mist overlay of its own. That was harmless
## while it was the only thing over its hex, but stacking it on HexCellView's
## now-opaque one darkened an explored hex roughly twice as much as an
## identical hex the camera had not hydrated — a seam that moved with the
## camera. One overlay per hex, owned by the view that exists for every hex.
func set_fog_state(state: GameEnums.FogState) -> void:
	modulate = FogVisuals.tint_color(state)

## Exposed so LocalDetailManager.get_props_at() can hand a hex's live prop
## scatter to MovementStepper's callers as steering obstacles. Returns a
## defensive copy, same "caller reads, doesn't own" convention as
## BuildingManager.get_buildings_at().
func get_props() -> Array[PropInstance]:
	return _props.duplicate()

## Pushed live by LocalDetailManager on every LOW<->MEDIUM<->HIGH band
## crossing — mirrors set_fog_state()'s "update in place" shape, and (unlike
## before) only touches the parts that actually depend on fidelity; see
## _rebuild_fidelity_dependent()'s own doc comment.
func set_fidelity(fidelity: GameEnums.TacticalFidelity) -> void:
	if fidelity == _fidelity:
		return
	_fidelity = fidelity
	if is_inside_tree():
		_rebuild_fidelity_dependent()

func _redraw() -> void:
	for child in get_children():
		child.queue_free()

	# No ground layer here. This used to build a SubHexGroundView — an 11x11
	# grid of square terrain sprites per hex — and TerrainMeshView then drew
	# the real polygon geometry on top of it. "remove all of the sub hex tile
	# biome square tiles please and just use the polygon derived map" (user,
	# 2026-08-18): the squares are gone, and ground is now exactly two layers,
	# neither of them per-hex — TerrainMeshView's vector mesh at z_index -1,
	# over HexGridMap's flat per-hex tile at -3 wherever no chunk is baked.
	# The -2 band this occupied is deliberately left vacant rather than
	# reclaimed; anything added there would sit between them.
	add_child(_build_grid_outline())  # Always-on structural hex boundary — a SEPARATE layer from the ZoC outline below, not the same line reused.

	add_child(_build_zoc_overlay())  # Ground-level tint — drawn before props/buildings so they render on top of it, not under.

	_props_layer = Node2D.new()
	_props_layer.name = "Props"
	add_child(_props_layer)

	_buildings_layer = Node2D.new()
	_buildings_layer.name = "Buildings"
	add_child(_buildings_layer)

	_rebuild_fidelity_dependent()


## Rebuilds ONLY the two things that depend on `_fidelity` — props (blob at
## LOW, real per-type shape at MEDIUM/HIGH) and buildings (flat
## category-color box at LOW, real sprite+effects at MEDIUM/HIGH; see this
## class's own doc comment) — by clearing and repopulating _props_layer/
## _buildings_layer in place. Their own position among this node's children
## (and therefore draw order relative to ground/outline/ZoC/fog) never
## changes, so no re-parenting/move_child() bookkeeping is needed the way
## LocalDetailManager's _wall_layer requires for the same class of problem.
## Called by _redraw() (fresh hydration) AND set_fidelity() (an
## already-hydrated hex crossing a fidelity band) — splitting this out of a
## full _redraw() fixed a real perf issue: every fidelity crossing used to
## needlessly re-run the square ground's expensive 121-sample real-terrain
## compositing (since removed entirely) and tear down/rebuild every
## building's particle systems, even though neither actually changes with
## fidelity at all.
func _rebuild_fidelity_dependent() -> void:
	for child in _props_layer.get_children():
		child.queue_free()
	for child in _buildings_layer.get_children():
		child.queue_free()
	_building_containers.clear()

	for prop in _props:
		_props_layer.add_child(_build_prop_node(prop))

	for i in range(_buildings.size()):
		var building := _buildings[i]
		var container := _build_building_node(building, i)
		_buildings_layer.add_child(container)
		_building_containers[building.id] = container
		if _selected_building and building.id == _selected_building.id:
			container.modulate = _SELECTED_TINT

## A genuinely separate, always-visible Line2D (same thin dark stroke
## HexCellView's own _outline establishes for Strategic zoom) — never gated
## by DisplaySettings.show_zoc_tactical or anything else. Fixes a bug where
## toggling off the ZoC display option also erased the ONLY hex-boundary
## line in Tactical view: the terrain under this draws no hex boundary of
## its own — deliberately, since TerrainMeshView's geometry does not know
## about hexes at all — so _build_zoc_overlay()'s Military ZoC outline
## (below) was doing double duty as the de facto hex grid on most settled
## hexes, and unticking ZoC incidentally erased grid lines that have
## nothing to do with it.
func _build_grid_outline() -> Line2D:
	var outline := Line2D.new()
	outline.name = "GridOutline"
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color(0.0, 0.0, 0.0, 0.35)
	outline.points = HexCoord.corner_points(Vector2.ZERO)
	return outline

## Zone of Control, Tactical surface — see ZoneOfControlVisuals.gd's own doc
## comment for the outline-vs-fill shape shared with StrategicOverlayManager's
## world-view copy. Always built (even with no _zoc_state at all — a plain
## hidden container) so _update_zoc_overlay()/set_zoc_state() always have a
## real node to toggle.
func _build_zoc_overlay() -> Node2D:
	var container := Node2D.new()
	container.name = "ZocOverlay"

	var outline := Line2D.new()
	outline.name = "MilitaryOutline"
	outline.closed = true
	outline.default_color = ZoneOfControlVisuals.MILITARY_OUTLINE_COLOR
	outline.width = ZoneOfControlVisuals.MILITARY_OUTLINE_WIDTH
	outline.points = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(outline)

	var fill := Polygon2D.new()
	fill.name = "CivilianFill"
	fill.color = ZoneOfControlVisuals.CIVILIAN_FILL_COLOR
	fill.polygon = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(fill)

	_update_zoc_overlay_on(container)
	return container

func _update_zoc_overlay() -> void:
	var container := get_node_or_null("ZocOverlay")
	if container:
		_update_zoc_overlay_on(container)

func _update_zoc_overlay_on(container: Node2D) -> void:
	var has_military := _zoc_state != null and _zoc_state.has_military_coverage()
	var has_civilian := _zoc_state != null and _zoc_state.has_civilian_coverage
	(container.get_node("MilitaryOutline") as Line2D).visible = has_military and DisplaySettings.show_zoc_tactical
	(container.get_node("CivilianFill") as Polygon2D).visible = has_civilian and DisplaySettings.show_zoc_tactical

## Real per-species prop art (PropVisuals.prop_texture()), Sprite2D-scaled-
## to-a-target-diameter same as TacticalEntityLayer._build_unit_figure()/
## _build_zombie_figure() — a prop's own species silhouette has no
## pre-existing quad to texture onto (each _prop_polygon() shape is an
## irregular hand-drawn silhouette, not a quad), so a standalone sprite is
## correct here rather than a UV-mapped Polygon2D. Only consulted at
## MEDIUM/HIGH — LOW keeps its uniform procedural blob regardless. Falls
## back to the procedural polygon per-prop wherever no art exists yet.
const PROP_SPRITE_DIAMETER: float = 20.0

func _build_prop_node(prop: PropInstance) -> Node2D:
	var texture := PropVisuals.prop_texture(prop.prop_type) if _fidelity != GameEnums.TacticalFidelity.LOW else null
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = prop.local_position
		sprite.rotation = prop.rotation
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * ((PROP_SPRITE_DIAMETER * prop.scale) / largest_dim)
		return sprite

	var shape := Polygon2D.new()
	shape.polygon = _low_fidelity_blob() if _fidelity == GameEnums.TacticalFidelity.LOW else _prop_polygon(prop.prop_type)
	shape.color = _prop_color(prop.prop_type)
	shape.position = prop.local_position
	shape.rotation = prop.rotation
	shape.scale = Vector2.ONE * prop.scale
	return shape

func _low_fidelity_blob() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * 5.0)
	return points

func _prop_polygon(prop_type: GameEnums.PropType) -> PackedVector2Array:
	match prop_type:
		GameEnums.PropType.TREE:
			return PackedVector2Array([Vector2(0, -10), Vector2(6, 6), Vector2(-6, 6)])
		GameEnums.PropType.ROCK:
			return PackedVector2Array([Vector2(-5, 4), Vector2(0, -5), Vector2(5, 4), Vector2(2, 6), Vector2(-2, 6)])
		GameEnums.PropType.REED:
			return PackedVector2Array([Vector2(-1, 8), Vector2(1, 8), Vector2(0, -10)])
		_:  # BUSH
			return PackedVector2Array([Vector2(-5, 3), Vector2(-3, -4), Vector2(3, -4), Vector2(5, 3), Vector2(0, 5)])

func _prop_color(prop_type: GameEnums.PropType) -> Color:
	match prop_type:
		GameEnums.PropType.TREE:
			return Color(0.20, 0.35, 0.16)
		GameEnums.PropType.BUSH:
			return Color(0.28, 0.42, 0.22)
		GameEnums.PropType.ROCK:
			return Color(0.45, 0.44, 0.42)
		GameEnums.PropType.REED:
			return Color(0.42, 0.46, 0.20)
		_:
			return Color(0.3, 0.3, 0.3)

## Real per-building-type sprite art (BuildingVisuals.building_texture())
## replaces the flat category-color square where authored — a plain
## 4-corner uv mapping onto a 4-vertex quad: a rectangle-to-rectangle corner
## correspondence is a single, exact affine map across the whole quad, not
## the hex-fan case that risks non-affine sampling (see HexCellView's own
## doc comment). Falls back to the flat box for any type with no SVG
## authored yet.
##
## `Polygon2D.uv` is in the texture's own PIXEL-space, not normalized 0..1,
## unlike most UV conventions in graphics — a `(0,0)-(1,1)` unit-square uv
## array only ever samples a literal 1x1-pixel patch in the texture's
## top-left corner, stretched across the whole polygon. For this project's
## 2048x2048 AI-generated building art (real transparent margin around the
## illustration), that 1x1 sample lands on transparent background almost
## always, rendering the fill invisible and leaving only the outline. Fix:
## uv corners must be the texture's REAL pixel dimensions — quad_uv() below
## is shared by every call site that textures a plain quad (this class, the
## ghost-preview building in BuildPlacementController, the Ditch/Oil Pit
## defense-work icon in the wall overlay renderer) rather than each
## hand-rolling the same wrong array.
static func quad_uv(texture: Texture2D) -> PackedVector2Array:
	if not texture:
		return PackedVector2Array()
	var size := texture.get_size()
	return PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)])

## Half-width of an intact building's box, in world units — derived from
## HexCoord.HEX_SIZE rather than picked purely by "does it read at a
## glance": HexCoord.WORLD_UNITS_PER_REAL_METER is the shared real-world/
## world-unit ratio, and a representative building footprint of 100m x 100m
## (50m half-width, sized for a large Victorian civic/industrial complex
## since one uniform box stands in for every building type from a Gas
## Streetlamp up to a Town Hall) converts to ~5.13 world units half-size at
## that ratio. BUILDING_SIZE_MULTIPLIER (4x) sits on top of that
## real-scale figure as an explicit, named legibility override — true-to-
## scale reads too small to make out at a glance even with real sprite art
## on it, so this stays a separate named fudge rather than inflating the
## base figure and losing its derivation.
const BUILDING_SIZE_MULTIPLIER: float = 4.0
const BUILDING_HALF_SIZE: float = HexCoord.WORLD_UNITS_PER_REAL_METER * 50.0 * BUILDING_SIZE_MULTIPLIER
## Ring radius _resolved_building_position() spreads stacked buildings over
## — must clear BUILDING_HALF_SIZE's own center-to-corner half-diagonal
## (5.128 * sqrt(2) ≈ 7.25) with margin, scaled by the same
## BUILDING_SIZE_MULTIPLIER so it stays correct as that constant changes.
const BUILDING_RING_RADIUS: float = 12.45 * BUILDING_SIZE_MULTIPLIER

## Radius for the shared gold selection ring drawn around a selected
## building (UnitCommandController) — derived from BUILDING_HALF_SIZE
## (~1.6x its corner-to-corner half-diagonal, BUILDING_HALF_SIZE * sqrt(2))
## rather than hardcoded in UnitCommandController, so it can't drift out of
## sync with BUILDING_HALF_SIZE/BUILDING_RING_RADIUS/ObstacleRadii.BUILDING_RADIUS
## the next time a building resize happens.
const BUILDING_SELECTION_RING_RADIUS: float = BUILDING_HALF_SIZE * 1.6

## `modulate` on the whole per-building container (not `box.color` — that
## field is either Color.WHITE, letting a real sprite's own colors show
## through, or the flat category_color() fallback; tinting it directly
## would fight one of those two rather than sit on top of either) so a
## selected building visibly shifts color regardless of which case it's
## currently in. Blue channel pushed above 1.0 — Godot's modulate
## multiplies each channel against whatever's already drawn, so this
## visibly brightens the building too, not just a flat color swap.
const _SELECTED_TINT := Color(0.55, 0.75, 1.55)

## White for a normal finished building, BuildingVisuals.construction_color()
## while it's still a construction site. set_building_selected() multiplies
## _SELECTED_TINT on top of this rather than always overwriting to White, so
## a mid-construction building that gets selected still reads as "under
## construction" instead of losing that tint when clicked.
func _building_base_modulate(building: BuildingInstance) -> Color:
	return BuildingVisuals.construction_color() if building.is_under_construction else Color.WHITE

func _build_building_node(building: BuildingInstance, index: int) -> Node2D:
	var container := Node2D.new()
	container.modulate = _building_base_modulate(building)
	var box := Polygon2D.new()
	if building.is_ruined:
		# A jagged rubble silhouette, deliberately distinct from every
		# intact building's clean square. Ruins stay code-drawn regardless
		# of whether the intact building has real art — a collapsed
		# building has no sprite.
		box.color = BuildingVisuals.ruin_color()
		box.polygon = _scaled_polygon(_ruin_polygon(), BUILDING_HALF_SIZE / 10.0)  # _ruin_polygon()'s own points were hand-authored at the old half=10 scale — resize with it rather than redrawing it by hand.
	else:
		var half := BUILDING_HALF_SIZE
		box.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
		# LOW fidelity skips the real sprite the same way props already
		# simplify to a blob — a flat category-color box instead of a
		# 2048x2048 texture, reusing the SAME fallback an unauthored
		# building type already falls back to (see this class's own doc
		# comment). MEDIUM/HIGH both show the real sprite.
		var texture: Texture2D = null
		if _fidelity != GameEnums.TacticalFidelity.LOW:
			texture = BuildingVisuals.building_texture(building.definition.building_type)
		if texture:
			box.texture = texture
			box.uv = quad_uv(texture)
			box.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			box.color = Color.WHITE  # let the sprite's own colors show — category_color() was only ever a stand-in for this.
		else:
			box.color = BuildingVisuals.category_color(building.definition.category)
	container.add_child(box)

	container.position = _resolved_building_position(building, index)

	if not building.is_ruined and not building.is_under_construction:
		_attach_effects(container, building.definition)

	return container

## Smoke/fire/light particle effects — see BuildingEffectsVisuals' own doc
## comment for what qualifies a building for which. Ruins have nothing left
## to smoke or glow; a construction site isn't operating yet either.
## `_effect_anchor` is a fixed fraction of BUILDING_HALF_SIZE (roughly "roof
## height"), not a real per-model chimney position — these are deliberately
## simple, generic effects, not bespoke per-building placement.
const _EFFECT_ANCHOR_Y: float = -BUILDING_HALF_SIZE * 0.5

func _attach_effects(container: Node2D, definition: BuildingDefinition) -> void:
	# Particle sims (CPUParticles2D) are a real per-frame CPU cost, unlike
	# the light glow below (a static Sprite2D + GPU shader, no simulation) —
	# skipped at LOW fidelity, the band with the most buildings likely on
	# screen at once, same reasoning the building sprite skip above uses.
	if _fidelity != GameEnums.TacticalFidelity.LOW:
		if BuildingEffectsVisuals.has_fire(definition):
			var fire := BuildingEffectsVisuals.build_fire_particles()
			fire.position = Vector2(0, _EFFECT_ANCHOR_Y)
			container.add_child(fire)
			var smoke := BuildingEffectsVisuals.build_smoke_particles()  ## A real furnace/foundry smokes AND burns — has_fire() implies has_smoke() would also be true, but check independently rather than assuming that stays paired forever.
			smoke.position = Vector2(0, _EFFECT_ANCHOR_Y)
			container.add_child(smoke)
		elif BuildingEffectsVisuals.has_smoke(definition):
			var smoke := BuildingEffectsVisuals.build_smoke_particles()
			smoke.position = Vector2(0, _EFFECT_ANCHOR_Y)
			container.add_child(smoke)

	if BuildingEffectsVisuals.has_light(definition):
		container.add_child(BuildingEffectsVisuals.build_light_glow())

func _ruin_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-10, -6), Vector2(-4, -10), Vector2(3, -7), Vector2(10, -9), Vector2(9, 2), Vector2(4, 10), Vector2(-6, 8), Vector2(-9, 3)])

func _scaled_polygon(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	scaled.resize(points.size())
	for i in range(points.size()):
		scaled[i] = points[i] * factor
	return scaled

## Buildings placed through the plain hex-coordinate API (BuildingManager.place_building()
## with no explicit local_position) all default to the hex center, which
## would otherwise stack them on top of each other here. Spread those out
## into a small deterministic ring purely for legibility.
func _resolved_building_position(building: BuildingInstance, index: int) -> Vector2:
	if building.local_position != Vector2.ZERO or index == 0:
		return building.local_position
	var angle := TAU * float(index) / float(_buildings.size())
	return Vector2(cos(angle), sin(angle)) * BUILDING_RING_RADIUS
