class_name TacticalHexView
extends Node2D

## Close-zoom detail for one hex (Phase 2.5 "Tactical view"). Composes the
## same HexCellView already draws for Strategic — biome/soil stays a single
## source of visual truth — with a scatter of placeholder props and every
## BuildingInstance in this hex rendered at its own precise position,
## instead of one flat tile standing in for the whole ~5x5 mile area.
## Ground here is the same tiled-texture HexCellView Strategic's own
## instances use too now (see that class's own doc comment for the real
## rendering bug this used to differ over, and why it doesn't anymore).
## Spawned/freed by LocalDetailManager as the camera crosses the tactical
## zoom threshold and pans between hexes; only ever exists for a hex that
## has qualified as settled/frontier (see LocalDetailManager).
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
func setup(p_cell: HexCell, props: Array[PropInstance], buildings: Array[BuildingInstance], fog_state: GameEnums.FogState = GameEnums.FogState.VISIBLE, fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH, zoc_state: ZoneOfControlState = null) -> void:
	cell = p_cell
	_props = props
	_buildings = buildings
	_fidelity = fidelity
	_zoc_state = zoc_state
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

	var ground := HexCellView.new()
	ground.setup(cell)
	add_child(ground)

	add_child(_build_zoc_overlay())  # Ground-level tint — drawn before props/buildings so they render on top of it, not under.

	for prop in _props:
		add_child(_build_prop_node(prop))

	for i in range(_buildings.size()):
		add_child(_build_building_node(_buildings[i], i))

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

func _build_prop_node(prop: PropInstance) -> Node2D:
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
## few points and interpolated), so this doesn't reproduce that bug. Falls
## back to the original flat box for any type with no SVG authored yet —
## exactly TerrainVisuals.terrain_texture()'s own "art lands incrementally,
## zero code changes elsewhere" contract.
## (A PackedVector2Array literal built from Vector2() calls isn't a valid
## GDScript `const` expression — Godot's static const evaluator rejects
## nested constructor calls in an array literal — so this is a plain
## function, computed fresh each call like `_ruin_polygon()` below.)
static func _box_uv() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])

func _build_building_node(building: BuildingInstance, index: int) -> Node2D:
	var box := Polygon2D.new()
	if building.is_ruined:
		# Phase 5.12: a jagged rubble silhouette, deliberately distinct from
		# every intact building's clean square — "a visible scar", not just
		# a recolored box. Ruins stay code-drawn regardless of whether the
		# intact building has real art — a collapsed building has no sprite.
		box.color = BuildingVisuals.ruin_color()
		box.polygon = _ruin_polygon()
	else:
		var half := 10.0
		box.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
		var texture := BuildingVisuals.building_texture(building.definition.building_type)
		if texture:
			box.texture = texture
			box.uv = _box_uv()
			box.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			box.color = Color.WHITE  # let the sprite's own colors show — category_color() was only ever a stand-in for this.
		else:
			box.color = BuildingVisuals.category_color(building.definition.category)
	box.position = _resolved_building_position(building, index)
	return box

func _ruin_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-10, -6), Vector2(-4, -10), Vector2(3, -7), Vector2(10, -9), Vector2(9, 2), Vector2(4, 10), Vector2(-6, 8), Vector2(-9, 3)])

## Buildings placed through the plain hex-coordinate API (BuildingManager.place_building()
## with no explicit local_position) all default to the hex center, which
## would otherwise stack them directly on top of each other here. Spread
## those out into a small deterministic ring purely for legibility — a real
## placement UI (Phase 6+) will set distinct local_positions of its own and
## this fallback won't trigger.
func _resolved_building_position(building: BuildingInstance, index: int) -> Vector2:
	if building.local_position != Vector2.ZERO or index == 0:
		return building.local_position
	var ring_radius := 22.0
	var angle := TAU * float(index) / float(_buildings.size())
	return Vector2(cos(angle), sin(angle)) * ring_radius
