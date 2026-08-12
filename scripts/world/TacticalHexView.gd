class_name TacticalHexView
extends Node2D

## Close-zoom detail for one hex (Phase 2.5 "Tactical view"). Composes a
## scatter of placeholder props and every BuildingInstance in this hex
## rendered at its own precise position, instead of one flat tile
## standing in for the whole ~5x5 mile area.
## Ground here is SubHexGroundView — real sub-hex land-cover/elevation/
## water data (RealTerrainSampler, baked offline from OpenStreetMap +
## AWS/Mapzen open data) composited from the same 11 terrain SVGs
## Strategic's own HexCellView uses, instead of one uniform tile standing
## in for the whole hex — see SubHexGroundView's own doc comment for the
## full reasoning (including why it deliberately avoids the two
## Polygon2D UV pitfalls this project has already been bitten by twice).
## Falls back to the flat HexCellView tile if the terrain bake hasn't
## been run/committed. Spawned/freed by LocalDetailManager as the camera
## crosses the tactical zoom threshold and pans between hexes; only ever
## exists for a hex that has qualified as settled/frontier (see
## LocalDetailManager).
##
## Phase 2.5.5 (LOD): `fidelity` only affects PROPS — at LOW it collapses
## every per-species polygon (tree/bush/rock/reed) down to one uniform
## blob shape, still colored by prop type, matching the design doc's own
## "simple silhouettes/blobs" language for the lowest Tactical band.
## MEDIUM and HIGH both draw today's real per-type polygons unchanged —
## the design doc's own tier descriptions only call out a MEDIUM-vs-HIGH
## distinction for UNITS ("tell a unit's role/tier apart" vs "individual-
## figure detail", see TacticalEntityLayer), not for props/buildings, so
## there's no fabricated difference to invent here without real art
## (Phase 6.3) to actually make HIGH "more elaborate" than MEDIUM.
## **Decided: buildings are NOT simplified at any fidelity** — their
## BuildingVisuals.category_color() box (still the fallback for any building
## type with no art authored — see the real-art note below) is already the
## single simplest shape that still carries the "which building category is
## this" signal LOW fidelity's own "tell unit from building from zombie
## apart" bar depends on; simplifying it further would remove exactly the
## cue that bar needs, not reduce needless detail. Real per-type sprite art
## (BuildingVisuals.building_texture(), Phase 6.3) now renders on that same
## square at every fidelity alike, same as terrain's own art landing without
## touching the LOD tiers at all — this was never a fidelity distinction to
## begin with, and still isn't.

var cell: HexCell
var _props: Array[PropInstance] = []
var _buildings: Array[BuildingInstance] = []
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH
var _zoc_state: ZoneOfControlState
## BuildingInstance.id -> the Node2D _build_building_node() returned for it,
## rebuilt every _redraw() — lets set_building_selected() re-tint one
## building in place without a full redraw, same "update in place" shape
## set_fog_state()/set_fidelity() below already follow for their own state.
var _building_containers: Dictionary = {}  # int -> Node2D
## Whichever of THIS hex's own buildings (if any) is the game's current
## single selection, threaded through setup() so a hex that dehydrates and
## rehydrates while its own building stays selected (camera pans away and
## back) redraws already knowing to highlight it — same reasoning
## `_fidelity`/`_zoc_state` are threaded through setup() for their own live
## state rather than always starting blank.
var _selected_building: BuildingInstance

func _ready() -> void:
	position = HexCoord.axial_to_world(cell.coord)
	DisplaySettings.changed.connect(_on_display_settings_changed)
	if cell:
		_redraw()

## Call before this node enters the tree; mirrors HexCellView.setup()'s
## defer-to-_ready() pattern since child nodes don't exist until _ready() runs.
## `fog_state` defaults to VISIBLE: LocalDetailManager only ever hydrates a
## hex that's at least EXPLORED (Phase 2.6), so the only two values that
## actually arrive here are EXPLORED (dimmed) and VISIBLE (full color).
## `zoc_state` (Zone of Control, design doc Phase 2.3, visualized for the
## first time this pass — user request) defaults to null, meaning "no
## LogisticsNetwork wired" — same "gracefully skip it" convention every
## other optional dependency in this project follows.
## `selected_building` (user request: real per-building selection highlight)
## defaults to null, meaning "nothing of this hex's is currently selected" —
## LocalDetailManager passes its live UnitCommandController-sourced value in
## on every hydrate, same as it already does for `fidelity`/`zoc_state`.
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

## Zone of Control (Phase 2.3): pushed live by LocalDetailManager whenever
## LogisticsNetwork recomputes — mirrors set_fidelity()'s "update in place,
## only redraw if it actually changed" shape.
func set_zoc_state(zoc_state: ZoneOfControlState) -> void:
	_zoc_state = zoc_state
	if is_inside_tree():
		_update_zoc_overlay()

## Display Options (user request): toggles this hex's own ZoC overlay live
## without a full redraw — the overlay node already exists (or doesn't,
## if no ZoC applies here), just its visibility needs to follow the flag.
func _on_display_settings_changed() -> void:
	_update_zoc_overlay()

## Selection-highlight sync (LocalDetailManager) — re-tints just the one
## matching container in place, same "update in place, no full redraw"
## shape set_fog_state()/set_fidelity() already follow. `instance` is
## always one of THIS hex's own buildings in practice (LocalDetailManager
## looks the owning hex up via BuildingInstance.hex_coord before ever
## calling this); the `_building_containers` lookup is a no-op rather than
## an error if that's ever not the case.
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

## Fog of War (Phase 2.6): dims the whole hydrated hex (terrain, props and
## buildings together) rather than the inner ground HexCellView alone, so a
## remembered-but-not-currently-visible hex reads as one dimmed scene.
func set_fog_state(state: GameEnums.FogState) -> void:
	modulate = FogVisuals.tint_color(state)

## Design doc, user request (local obstacle avoidance): `_props` was
## previously read only by this class's own `_redraw()` — exposed now so
## `LocalDetailManager.get_props_at()` can hand a hex's live prop scatter to
## `MovementStepper`'s callers as steering obstacles. Returns a defensive
## copy, same "caller reads, doesn't own" convention as
## `BuildingManager.get_buildings_at()`.
func get_props() -> Array[PropInstance]:
	return _props.duplicate()

## Phase 2.5.5: pushed live by LocalDetailManager on every LOW<->MEDIUM<->HIGH
## band crossing — mirrors set_fog_state()'s "update in place, only redraw if
## it actually changed" shape rather than a full dehydrate/rehydrate.
func set_fidelity(fidelity: GameEnums.TacticalFidelity) -> void:
	if fidelity == _fidelity:
		return
	_fidelity = fidelity
	if is_inside_tree():
		_redraw()

func _redraw() -> void:
	for child in get_children():
		child.queue_free()
	_building_containers.clear()

	var ground := SubHexGroundView.new()
	ground.setup(cell)
	add_child(ground)

	add_child(_build_grid_outline())  # Always-on structural hex boundary — see that function's own doc comment for why this is a SEPARATE layer from the ZoC outline below, not the same line reused.

	add_child(_build_zoc_overlay())  # Ground-level tint — drawn before props/buildings so they render on top of it, not under.

	for prop in _props:
		add_child(_build_prop_node(prop))

	for i in range(_buildings.size()):
		var building := _buildings[i]
		var container := _build_building_node(building, i)
		add_child(container)
		_building_containers[building.id] = container
		if _selected_building and building.id == _selected_building.id:
			container.modulate = _SELECTED_TINT

## **Real bug fix (playtest round 4, #10): "the hex tile grid borders
## disappear when the display option 'Zone of Control (tactical view)' is
## unticked... and you zoom out and zoom back in"** — before this fix,
## `_build_zoc_overlay()`'s olive-green `MilitaryOutline` below (a genuine
## ZoC visualization, `ZoneOfControlVisuals.MILITARY_OUTLINE_COLOR`) was the
## ONLY hex-boundary line drawn anywhere in Tactical view at all —
## `SubHexGroundView`'s real sub-hex terrain has no outline of its own (only
## its `HexCellView` no-data fallback does). Since most settled hexes carry
## Military ZoC coverage, that outline was doing double duty as the de facto
## "hex grid" the player actually relies on for navigation — so unticking
## the ZoC display option (which correctly hides ONLY the ZoC visualization,
## exactly as it's supposed to) incidentally erased the only grid lines that
## existed at all, and only became visible once a hex actually re-hydrated
## (LocalDetailManager's zoom-out/in cycle re-triggering `_redraw()`) applied
## the new setting for the first time. This is a genuinely separate, always-
## visible `Line2D` (same thin dark stroke `HexCellView`'s own `_outline`
## already establishes for Strategic zoom) — never gated by
## `DisplaySettings.show_zoc_tactical` or anything else — so basic hex-grid
## legibility can never depend on an unrelated display toggle again.
func _build_grid_outline() -> Line2D:
	var outline := Line2D.new()
	outline.name = "GridOutline"
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color(0.0, 0.0, 0.0, 0.35)
	outline.points = HexCoord.corner_points(Vector2.ZERO)
	return outline

## Zone of Control (Phase 2.3), Tactical surface — see
## `ZoneOfControlVisuals.gd`'s own doc comment for the outline-vs-fill shape
## reasoning shared with `StrategicOverlayManager`'s own world-view copy.
## Always built (even with no `_zoc_state` at all — a plain hidden
## container) so `_update_zoc_overlay()`/`set_zoc_state()` always have a
## real node to toggle rather than needing to lazily create one on first
## use.
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

## Real per-species prop art (PropVisuals.prop_texture(), user request this
## pass — see assets/props/README.md), Sprite2D-scaled-to-a-target-diameter
## same as TacticalEntityLayer._build_unit_figure()/_build_zombie_figure()
## already do — a prop's own species silhouette has no pre-existing quad or
## hex to texture onto (each _prop_polygon() shape is an irregular hand-drawn
## silhouette, not a quad — texturing it via uv would risk the exact
## non-affine sampling bug TerrainVisuals/HexCellView's own doc comment
## already documents and fixed once), so a standalone sprite is the correct
## choice here, not a UV-mapped Polygon2D. Only consulted at MEDIUM/HIGH —
## LOW keeps its uniform procedural blob regardless (PropVisuals' own doc
## comment). Falls back to the original procedural polygon per-prop wherever
## no art exists yet, same "art lands incrementally" contract as everywhere
## else in this project.
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

## LOW fidelity (Phase 2.5.5): one uniform blob shape for every prop
## species — still colored by prop type (_prop_color() below, untouched),
## just without the per-species silhouette MEDIUM/HIGH draw.
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

## Phase 6.3: real per-building-type sprite art (BuildingVisuals.building_texture())
## replaces the flat category-color square where authored — a plain 4-corner
## uv mapping onto a 4-vertex quad, unlike the hex-fan case HexCellView's own
## doc comment warns about: a rectangle-to-rectangle corner correspondence IS
## a single, exact affine map across the WHOLE quad (not just sampled at a
## few points and interpolated), so this doesn't reproduce THAT bug. Falls
## back to the original flat box for any type with no SVG authored yet —
## exactly TerrainVisuals.terrain_texture()'s own "art lands incrementally,
## zero code changes elsewhere" contract.
##
## **Real bug found and fixed (player report, "buildings still not visible" —
## the THIRD report of that symptom, after two same-day fixes that never
## actually re-screenshotted the result): `Polygon2D.uv` is in the texture's
## own PIXEL-space, not normalized 0..1, unlike virtually every other UV
## convention in graphics — a well-documented Godot gotcha (see
## godotengine/godot#21830 and community write-ups; Godot's own class docs
## don't state this explicitly, which is exactly how it went unnoticed
## here). A `(0,0)-(1,1)` "unit square" uv array — what this function, the
## ghost-preview building in `BuildPlacementController`, and the Ditch/Oil
## Pit defense-work icon in `StrategicOverlayManager` all independently
## wrote — only ever samples a literal 1x1-PIXEL patch in the texture's own
## top-left corner, stretched across the whole polygon. For this project's
## AI-generated building art (2048x2048 canvases with real transparent
## margin around the illustration), that 1x1 sample lands on fully
## transparent background essentially every time — rendering as a
## perfectly invisible fill, leaving only the (separately-drawn) outline
## on screen. Every building in the game has been invisible for this
## reason since Phase 6.3's real art landed, regardless of camera
## position/box size/outline color — none of which were ever the actual
## bug despite two prior fix attempts at exactly those things.
## **Fix:** uv corners must be the texture's REAL pixel dimensions, not a
## unit square — `quad_uv()` below is now public and shared by all three
## call sites above rather than each hand-rolling the same wrong array.
static func quad_uv(texture: Texture2D) -> PackedVector2Array:
	if not texture:
		return PackedVector2Array()
	var size := texture.get_size()
	return PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)])

## Half-width of an intact building's box, in world units. **Found while
## investigating a user report ("I can't see any buildings on the map") —
## this was still 10.0 from before Phase 2.5.6's 8x HexCoord.HEX_SIZE
## increase (64 -> 512) and never got rescaled alongside it, unlike
## TacticalEntityLayer.FIGURE_RADIUS (units) which explicitly did (see that
## class's own doc comment on being "raised 19.2x" for exactly this reason).
## A 20-unit box against a 512-unit hex radius rendered at under 4px even at
## HIGH tactical fidelity — sub-pixel, not just "small," confirmed empirically
## (placed two different building types, zoomed to within one step of
## max_zoom, neither ever became visible).
## **Raised a second time (35 -> 70)** after a first pass at this fix (still
## not enough per a follow-up user report) — a headless diagnostic proved
## the render data itself was already correct at 35 (right polygon, right
## position, right texture, all visible=true), so the actual problem that
## pass was CameraController's own starting position being several hexes
## off Manchester (see Main.gd, fixed separately) rather than pure size —
## but a building that's still easy to overlook at a glance even when
## you're looking straight at the right hex isn't fully fixed either;
## doubling it removes that ambiguity rather than requiring pixel-perfect
## camera alignment to ever spot one.
## Sized instead off this project's own established "tactical figure" scale
## rather than a hex-fraction ratio (real building footprints are a
## meaningless fraction of a true ~5-mile hex; legibility is what matters,
## same reasoning TacticalEntityLayer's own doc comment gives): bigger than
## a squad's scatter footprint (FIGURE_SPREAD 20 => ~40 diameter) and bigger
## than a Tier 4/5 vehicle (VEHICLE_RADIUS 16 => 32 diameter) — a building
## should read as the most prominent thing in a hex besides terrain itself.
##
## **Superseded (player report, "buildings should be scaled correctly,
## based on the fact that hex tiles are 5 miles by 5 miles... work out how
## big they need to be on the map based on the 5 mile by 5 mile hex
## tiles").** The reasoning above (and the two prior resizes it documents,
## 10 -> 35 -> 70) picked this purely by "does it read at a glance,"
## explicitly disclaiming any connection to the hex's own real scale — the
## user has now overridden that call directly, so this is derived from
## `HexCoord.HEX_SIZE` instead:
## - `HexCoord.WORLD_UNITS_PER_REAL_METER` is the shared real-world/world-unit
##   ratio (see that constant's own doc comment for the full derivation).
## - A REPRESENTATIVE building footprint of 100m x 100m (50m half-width —
##   sized for a large Victorian civic/industrial complex, since one
##   uniform box has to stand in for every building type this project has,
##   from a Gas Streetlamp up to a Town Hall) converts to ~5.13 world units
##   half-size at that ratio.
##
## **Bumped 4x again (user report: "increase the size of the buildings by
## 4x, they are too small at the moment").** The real-world derivation above
## is still the right REPRESENTATIVE footprint — this isn't a second
## real-scale recalculation, it's the same kind of deliberate legibility
## override the two resizes before the real-scale pass already made once
## (10 -> 35 -> 70, see that history above): true-to-scale reads as too
## small to make out at a glance even with real sprite art on it, so
## `BUILDING_SIZE_MULTIPLIER` sits on top of the real-scale figure as an
## explicit, named fudge rather than silently inflating the "50.0" itself
## and losing the derivation's own meaning.
const BUILDING_SIZE_MULTIPLIER: float = 4.0
const BUILDING_HALF_SIZE: float = HexCoord.WORLD_UNITS_PER_REAL_METER * 50.0 * BUILDING_SIZE_MULTIPLIER
## Ring radius _resolved_building_position() spreads stacked buildings over
## (see that function) — rescaled alongside BUILDING_HALF_SIZE so multiple
## buildings sharing a hex (Shift-click placement) don't visually overlap;
## must clear BUILDING_HALF_SIZE's own center-to-corner half-diagonal
## (5.128 * sqrt(2) = ~7.25), same ~1.72x margin the old 70/170 pair used —
## scaled by the same BUILDING_SIZE_MULTIPLIER so that margin stays correct
## at the new size instead of drifting out of sync with it.
const BUILDING_RING_RADIUS: float = 12.45 * BUILDING_SIZE_MULTIPLIER

## Adversarial code-review finding (this pass's own verification step):
## UnitCommandController's shared gold `_selection_ring` used a flat,
## unit-scoped radius (16.0) for building selection too, which predated
## BUILDING_HALF_SIZE's 4x bump — 16 no longer clears the box's own
## corner-to-corner half-diagonal (BUILDING_HALF_SIZE * sqrt(2), ~29.0), so
## the ring rendered INSIDE the building instead of around it, clashing
## with (and mostly hidden by) the new `_SELECTED_TINT` highlight. Exposed
## here — not hardcoded in UnitCommandController — so it stays derived from
## BUILDING_HALF_SIZE the same way BUILDING_RING_RADIUS/ObstacleRadii.BUILDING_RADIUS
## already are, rather than becoming a fourth hand-copied number that can
## drift out of sync the next time a building resize happens. ~1.6x margin
## over the half-diagonal — comfortably outside every corner, not just
## touching them.
const BUILDING_SELECTION_RING_RADIUS: float = BUILDING_HALF_SIZE * 1.6

## A dark outline used to be traced around EVERY building box, selected or
## not — user report ("I still can't see any buildings I place"), the
## second cause found alongside Main.gd's camera-recenter fix: the box
## itself was already rendering at the right size/position/texture
## (confirmed with a headless dump of the actual Polygon2D), it just wasn't
## READING as a building against this hex's own grey/brown cobblestone
## texture — real building art (a muted brown/tan illustration, same family
## of colors as the terrain under it) and the flat category_color()
## fallback both blend into the ground at a glance rather than popping the
## way FIGURE_RADIUS's bright unit circles or the props' saturated greens
## already do. An outline is color-agnostic — it makes the shape itself
## legible regardless of how close the fill color happens to land to
## whatever terrain is underneath, without needing to fight every
## individual building texture's own palette.
##
## **Superseded (user report: "remove the thick black boxes around the
## buildings and instead make a nicer selection highlight on the building
## itself... change the image colour to blue").** A permanent outline on
## EVERY building was never actually about selection — it was legibility
## padding for buildings that used to render at a sub-pixel-adjacent size
## (see BUILDING_HALF_SIZE's own doc history above). Now that buildings
## render 4x bigger, the outline reads as exactly what the report calls it:
## a heavy black box nobody asked for. Removed outright; the selection-only
## `_SELECTED_TINT` below takes over as the "is this a building" /
## "is this THE selected building" signal, with 4x the sprite/fill area
## itself now doing the legibility work the outline used to.
##
## `modulate` on the whole per-building container (not `box.color` — that
## field is either Color.WHITE, letting a real sprite's own colors show
## through, or the flat category_color() fallback; tinting it directly
## would fight one of those two rather than sit on top of either) so a
## selected building visibly shifts color regardless of which of those two
## cases it's currently in. Blue channel deliberately pushed above 1.0 —
## Godot's modulate multiplies each channel against whatever's already
## drawn, so this doesn't just recolor the building, it visibly brightens
## it too, closer to "this building just lit up" than a flat color swap.
const _SELECTED_TINT := Color(0.55, 0.75, 1.55)

## Returns the container's own idle-state modulate — White for a normal
## finished building, BuildingVisuals.construction_color() while it's still
## a construction site (user report — see that function's own doc comment).
## `set_building_selected()` below multiplies _SELECTED_TINT on top of this
## rather than always overwriting to White, so a mid-construction building
## that gets selected still visibly reads as "under construction" instead of
## losing that tint the instant it's clicked.
func _building_base_modulate(building: BuildingInstance) -> Color:
	return BuildingVisuals.construction_color() if building.is_under_construction else Color.WHITE

func _build_building_node(building: BuildingInstance, index: int) -> Node2D:
	var container := Node2D.new()
	container.modulate = _building_base_modulate(building)
	var box := Polygon2D.new()
	if building.is_ruined:
		# Phase 5.12: a jagged rubble silhouette, deliberately distinct from
		# every intact building's clean square — "a visible scar", not just
		# a recolored box. Ruins stay code-drawn regardless of whether the
		# intact building has real art — a collapsed building has no sprite.
		box.color = BuildingVisuals.ruin_color()
		box.polygon = _scaled_polygon(_ruin_polygon(), BUILDING_HALF_SIZE / 10.0)  # _ruin_polygon()'s own points were hand-authored at the old half=10 scale — resize with it rather than redrawing it by hand.
	else:
		var half := BUILDING_HALF_SIZE
		box.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
		var texture := BuildingVisuals.building_texture(building.definition.building_type)
		if texture:
			box.texture = texture
			box.uv = quad_uv(texture)
			box.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			box.color = Color.WHITE  # let the sprite's own colors show — category_color() was only ever a stand-in for this.
		else:
			box.color = BuildingVisuals.category_color(building.definition.category)
	container.add_child(box)

	container.position = _resolved_building_position(building, index)
	return container

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
## would otherwise stack them directly on top of each other here. Spread
## those out into a small deterministic ring purely for legibility — a real
## placement UI (Phase 6+) will set distinct local_positions of its own and
## this fallback won't trigger.
func _resolved_building_position(building: BuildingInstance, index: int) -> Vector2:
	if building.local_position != Vector2.ZERO or index == 0:
		return building.local_position
	var angle := TAU * float(index) / float(_buildings.size())
	return Vector2(cos(angle), sin(angle)) * BUILDING_RING_RADIUS
