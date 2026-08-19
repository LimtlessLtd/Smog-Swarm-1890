class_name WallVisuals
extends RefCounted

## Shared placeholder color-by-tier lookup for wall segments — same
## "*Visuals.gd" convention BuildingVisuals/TerrainVisuals/FogVisuals
## establish (a single source of truth so a color choice doesn't silently
## drift between callers, and so it's swappable for real art later without
## touching whatever triggers a marker). WallMarkerRenderer's Strategic-zoom
## wall markers are the only consumer today.

static func tier_color(tier: int) -> Color:
	match tier:
		WallCatalog.WOODEN:
			return Color(0.55, 0.42, 0.28)
		WallCatalog.BRICK:
			return Color(0.62, 0.30, 0.24)
		WallCatalog.CONCRETE:
			return Color(0.58, 0.58, 0.60)
		_:
			return Color(0.5, 0.5, 0.5)

## A breached segment — one dim, alarmed red regardless of tier, same
## reasoning BuildingVisuals.ruin_color() already gives for a ruined
## building's color: what it USED to be stops mattering once it's failed.
static func breached_color() -> Color:
	return Color(0.7, 0.16, 0.12)

## An intact Gate segment (WallSegment.is_gate) — one warm brass/gold tone
## regardless of tier, same "one flat color overrides tier_color()" shape
## breached_color() already uses, so a gate reads as "a gate" at a glance
## rather than needing the player to check its (lower) HP first. Only
## applies while intact — a breached gate still reads as breached_color(),
## same as any other segment (see _apply_wall_segment_look()'s priority
## order at the call site).
static func gate_color() -> Color:
	return Color(0.80, 0.64, 0.20)

## How the strip art in assets/walls/ maps onto a drawn wall, and the reason
## the wall stopped being a thin line inside a fat invisible band.
##
## Line2D tiles a texture along its length at a fixed texture-PIXELS-to-
## local-UNITS rate and stretches the texture's full HEIGHT across the
## line's width. So the art's aspect ratio and the drawn width are one
## decision, not two: pick a world length for one repeat, and the width that
## does not distort it follows. Authoring at one aspect and drawing at
## another is what squashed the old art, on top of it having occupied ~7% of
## its own image height to begin with ("Wall assets need to look more
## substantial, thicker" — user report).
##
## One repeat covers exactly one full-length wall PIECE. Each piece is its
## own Line2D starting the texture over at u=0, so a repeat per piece is
## what makes the pattern of a chained wall line up piece to piece instead
## of restarting mid-motif. tools/blender_pipeline/models/walls/strip.py
## holds the other half of this contract.
const TILE_WORLD_LENGTH: float = WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS

## span_y / span_x of the authored strips — see strip.STRIP_HEIGHT.
const STRIP_ASPECT_RATIO: float = 0.5

## The width every wall and gate is drawn at in Tactical view. Derived, not
## tuned: it is whatever keeps the art undistorted at TILE_WORLD_LENGTH.
## Per-TIER thickness is authored into the art's own band depth instead —
## drawing a wider line per tier would stretch a fixed-height texture by a
## different amount per tier, which reads as blur, not as mass.
const TACTICAL_WALL_WIDTH: float = TILE_WORLD_LENGTH * STRIP_ASPECT_RATIO

## Line thickness scales with tier — a Concrete wall should visibly read as
## sturdier than a Wooden one even before the player checks its HP. A
## breached segment renders at half its intact width (WallManager.gd's own
## HORDE_MARKER pattern of "still there, but visibly compromised" rather
## than vanishing outright — same idea HordeMarkerRenderer's own ghosted
## horde markers already use for "weaker/less current" state).
static func line_width(tier: int, breached: bool) -> float:
	var base := 3.0 + float(tier) * 2.0
	return base * 0.5 if breached else base

## Tactical-view width. Constant across tiers by construction (see
## TACTICAL_WALL_WIDTH); only a breach changes it, keeping line_width()'s own
## "still there, but visibly compromised" convention.
static func tactical_width(breached: bool) -> float:
	return TACTICAL_WALL_WIDTH * 0.5 if breached else TACTICAL_WALL_WIDTH

## A "legacy inner" wall (WallManager.is_legacy_segment()) — still fully
## functional, but no longer the settlement's outermost defended edge.
## Renders dimmed via the whole marker's `modulate` rather than a distinct
## hue, same "still there, just less current/prominent" idea
## HordeMarkerRenderer's own ghosted horde markers use for a
## not-currently-primary state — the segment's own tier/breached color
## already carries every mechanically-relevant fact (tier, HP state);
## legacy status is purely "how deep into my own territory this ring
## sits," a dimmer, not a fourth color to learn.
static func legacy_modulate() -> Color:
	return Color(1.0, 1.0, 1.0, 0.55)

## The counterpart to legacy_modulate() — full brightness, today's exact
## pre-4.1-decision look. A named constant (not a bare Color(1,1,1,1)
## inline) so both states read as an intentional pair at the call site.
static func outer_modulate() -> Color:
	return Color(1.0, 1.0, 1.0, 1.0)

## Lazily-loaded, cached TILEABLE strip texture for an intact wall segment
## (see `assets/walls/README.md`) — same `ResourceLoader.exists()`-gated-
## null pattern every other `*Visuals.gd` follows. Only for INTACT
## segments: a breached one keeps rendering as `breached_color()`'s flat
## alarm-red `Line2D` — a wall that's failed reads better as an obvious
## flat warning color than a tiled texture, same reasoning `ruin_color()`
## gives for a ruined building losing its category color. Applied via
## `Line2D.texture` + `texture_mode = Line2D.LINE_TEXTURE_TILE` at the call
## site (WallMarkerRenderer._apply_look()) — `Line2D` tiles a texture along
## its own length natively, no UV-mapping pitfall the way a `Polygon2D`
## would have (see TerrainVisuals/HexCellView's own documented bug on that).
static var _texture_cache: Dictionary = {}  # String (asset key) -> Texture2D (nullable)

static func tier_texture(tier: int) -> Texture2D:
	return _cached_texture(_texture_key(tier))

## A Gate has its own art rather than a tinted wall: it is a different
## structure (two piers and a pair of doors), it is a fixed three segments
## long, and it does not repeat — "There should be a seperate gate asset and
## it needs to be 3 wall segments long... but it shouldnt be repeatable/
## stretch like walls, you place 1 gate at a time" (user spec). gate_color()
## stays as the fallback tint for a tier whose gate art is not authored yet.
static func gate_texture(tier: int) -> Texture2D:
	return _cached_texture(_gate_texture_key(tier))

## The right art for whatever this segment actually is — nothing at all for a
## breached one, which keeps its flat alarm-red line (see tier_texture()'s
## own doc comment).
static func segment_texture(segment: WallSegment) -> Texture2D:
	if segment.is_breached():
		return null
	return gate_texture(segment.tier) if segment.is_gate else tier_texture(segment.tier)

## Everything about how one segment LOOKS, applied to a Line2D: art, tiling
## mode, tint and geometry. Shared by the Strategic marker, the Tactical
## marker and the placement preview, which previously each carried their own
## copy of this and had already drifted (only one of the three set
## texture_repeat). `final_width` stays the caller's decision because that is
## the one thing which genuinely differs between the zoom levels.
##
## Tiling mode is the substantive difference between a wall and a gate: a
## wall REPEATS along whatever length it was drawn at, a gate is one object
## stretched onto its own fixed length exactly once.
static func apply_segment_look(body: Line2D, segment: WallSegment, final_width: float) -> void:
	var texture := segment_texture(segment)
	body.texture = texture
	body.texture_mode = Line2D.LINE_TEXTURE_STRETCH if segment.is_gate else Line2D.LINE_TEXTURE_TILE
	body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Line2D multiplies the texture by default_color, so it has to be white
	# wherever real art is in play or the art comes out tinted.
	if texture:
		body.default_color = Color.WHITE
	elif segment.is_breached():
		body.default_color = breached_color()
	elif segment.is_gate:
		body.default_color = gate_color()
	else:
		body.default_color = tier_color(segment.tier)
	apply_line_geometry(body, segment.point_a, segment.point_b, final_width)

static func _cached_texture(key: String) -> Texture2D:
	if not _texture_cache.has(key):
		_texture_cache[key] = _load_texture(key)
	return _texture_cache[key]

## Line2D's LINE_TEXTURE_TILE mode maps texture PIXELS to local UNITS 1:1
## for its UV tiling (u = cumulative local-point distance /
## texture.get_width()) — independent of texture_repeat (that only controls
## whether u wrapping past 1.0 repeats or clamps). A placed wall PIECE is at
## most WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS (~10.26 world units)
## long, so fed straight in, a segment spans u in [0, 10.26/2048] — a sliver
## a few pixels wide stretched across the whole segment, which reads as a
## near-flat colour. Not a tiling-density tuning problem: the geometry was
## never long enough in LOCAL-point terms for Line2D's fixed pixel-to-unit
## convention to show more than a sliver, whatever texture_repeat said.
##
## Fixed the way a mismatched map-scale-vs-detail-scale problem always is:
## render in a coordinate space where the numbers work, then compensate with
## the node's own `scale` so the final on-screen geometry is unchanged.
## apply_line_geometry() feeds Line2D inflated LOCAL points (real segment
## vector * UV_SCALE) and sets `scale = 1/UV_SCALE` to shrink it back —
## Line2D bakes its UV from the pre-scale `points`, so this changes how many
## times the texture tiles WITHOUT moving either endpoint. `width` takes the
## same compensation for the same reason.
##
## DERIVED from the art and TILE_WORLD_LENGTH rather than hand-tuned, which
## is what makes "one repeat per full-length piece" true rather than
## approximately true: at STRIP_WIDTH_PX pixels per repeat, u reaches 1.0
## exactly when the real distance reaches TILE_WORLD_LENGTH. The previous
## hand-picked 1000.0 was fitted to a 4128px-wide texture that no longer
## exists, and silently became ~5 repeats per piece when the art was
## re-rendered at 2048.
const STRIP_WIDTH_PX: float = 2048.0
const UV_SCALE: float = STRIP_WIDTH_PX / TILE_WORLD_LENGTH

## Sets `body`'s points/position/scale/width so it renders as the true
## `point_a` -> `point_b` segment on screen while giving Line2D's own
## texture-tiling math a big enough LOCAL distance to actually show
## repeating detail — see this constant's own doc comment (UV_SCALE) for
## the full reasoning. `final_width` is the segment's real, on-screen line
## thickness (whatever line_width()-derived value the caller would
## otherwise have assigned to `body.width` directly) — this method does the
## UV_SCALE compensation for it, callers should never multiply it in
## themselves. Position/scale/points are the ONLY three properties this
## touches; texture/texture_mode/texture_repeat/default_color/modulate stay
## the call site's own responsibility (they don't interact with local-space
## geometry at all).
static func apply_line_geometry(body: Line2D, point_a: Vector2, point_b: Vector2, final_width: float) -> void:
	body.position = point_a
	body.rotation = 0.0
	body.scale = Vector2.ONE / UV_SCALE
	body.points = PackedVector2Array([Vector2.ZERO, (point_b - point_a) * UV_SCALE])
	body.width = final_width * UV_SCALE

static func _tier_key(tier: int) -> String:
	match tier:
		WallCatalog.WOODEN:
			return "wooden"
		WallCatalog.BRICK:
			return "brick"
		WallCatalog.CONCRETE:
			return "concrete"
		_:
			return ""

static func _texture_key(tier: int) -> String:
	var key := _tier_key(tier)
	return "" if key.is_empty() else "wall_%s" % key

static func _gate_texture_key(tier: int) -> String:
	var key := _tier_key(tier)
	return "" if key.is_empty() else "gate_%s" % key

static func _load_texture(key: String) -> Texture2D:
	if key.is_empty():
		return null
	var path := "res://assets/walls/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

