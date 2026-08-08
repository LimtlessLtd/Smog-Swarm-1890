class_name WallVisuals
extends RefCounted

## Shared placeholder color-by-tier lookup for wall segments — same
## "*Visuals.gd" convention BuildingVisuals/TerrainVisuals/FogVisuals
## already established (a single source of truth so a color choice doesn't
## silently drift between callers, and so it's swappable for real art
## later without touching whatever triggers a marker). StrategicOverlayManager's
## Strategic-zoom wall markers (Phase 2.7.3) are the only consumer today —
## walls have no dedicated Tactical-zoom visual of their own yet.

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

## Line thickness scales with tier — a Concrete wall should visibly read as
## sturdier than a Wooden one even before the player checks its HP. A
## breached segment renders at half its intact width (WallManager.gd's own
## HORDE_MARKER pattern of "still there, but visibly compromised" rather
## than vanishing outright — same idea Phase 2.7.6's ghosted horde markers
## already use for "weaker/less current" state).
static func line_width(tier: int, breached: bool) -> float:
	var base := 3.0 + float(tier) * 2.0
	return base * 0.5 if breached else base

## A "legacy inner" wall (WallManager.is_legacy_segment(), Phase 4.1) — still
## fully functional, but no longer the settlement's outermost defended edge.
## Renders dimmed via the whole marker's `modulate` rather than a distinct
## hue, same "still there, just less current/prominent" idea
## StrategicOverlayManager's own ghosted horde markers (Phase 2.7.6) already
## use for a not-currently-primary state — the segment's own tier/breached
## color already carries every mechanically-relevant fact (tier, HP state);
## legacy status is purely "how deep into my own territory this ring sits,"
## a dimmer, not a fourth color to learn.
static func legacy_modulate() -> Color:
	return Color(1.0, 1.0, 1.0, 0.55)

## The counterpart to legacy_modulate() — full brightness, today's exact
## pre-4.1-decision look. A named constant (not a bare Color(1,1,1,1)
## inline) so both states read as an intentional pair at the call site.
static func outer_modulate() -> Color:
	return Color(1.0, 1.0, 1.0, 1.0)

## Defense works (Ditch/Oil Pit, Phase 4.1) stack alongside a segment
## rather than replacing it — a small distinct marker color at the
## segment's midpoint on top of the line itself, not a second line.
static func defense_work_color(has_ditch: bool, has_oil_pit: bool) -> Color:
	if has_ditch and has_oil_pit:
		return Color(0.45, 0.32, 0.16)  # A muddy brown-orange blend reads as "both".
	if has_oil_pit:
		return Color(0.72, 0.42, 0.12)  # Warm amber-orange — oil.
	return Color(0.36, 0.30, 0.20)  # Dark earth — a ditch.

## Lazily-loaded, cached TILEABLE strip texture for an intact wall segment
## (user request, this pass — see `assets/walls/README.md`) — same
## `ResourceLoader.exists()`-gated-null pattern every other `*Visuals.gd`
## here follows. Only for INTACT segments: a breached one keeps rendering
## as `breached_color()`'s flat alarm-red `Line2D` (unchanged) — a wall
## that's failed reads better as an obvious flat warning color than a
## tiled texture, same reasoning `ruin_color()` already gives for a ruined
## building losing its category color. Applied via `Line2D.texture` +
## `texture_mode = Line2D.LINE_TEXTURE_TILE` at the call site
## (StrategicOverlayManager._apply_wall_segment_look()) — `Line2D` tiles a
## texture along its own length natively, no UV-mapping pitfall the way a
## `Polygon2D` would have (see TerrainVisuals/HexCellView's own documented
## bug on that).
static var _texture_cache: Dictionary = {}  # int (WallCatalog tier) -> Texture2D (nullable)

static func tier_texture(tier: int) -> Texture2D:
	if not _texture_cache.has(tier):
		_texture_cache[tier] = _load_texture(tier)
	return _texture_cache[tier]

static func _texture_key(tier: int) -> String:
	match tier:
		WallCatalog.WOODEN:
			return "wall_wooden"
		WallCatalog.BRICK:
			return "wall_brick"
		WallCatalog.CONCRETE:
			return "wall_concrete"
		_:
			return ""

static func _load_texture(tier: int) -> Texture2D:
	var key := _texture_key(tier)
	if key.is_empty():
		return null
	var path := "res://assets/walls/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Lazily-loaded, cached point icon for a defense work (Ditch/Oil Pit) at a
## segment's midpoint — same gated-null pattern, a Sprite2D-on-a-point
## rather than a tiled strip (a defense work sits at one spot, it doesn't
## run the segment's own length). `has_ditch`/`has_oil_pit` both true (both
## present) falls back to `defense_work_color()`'s existing blended-color
## Polygon2D — a "both present" icon is a real, separate asset nobody's
## authored, not worth inventing a compositing scheme for a placeholder.
static var _defense_work_texture_cache: Dictionary = {}  # String (key) -> Texture2D (nullable)

static func defense_work_texture(has_ditch: bool, has_oil_pit: bool) -> Texture2D:
	if has_ditch and has_oil_pit:
		return null
	var key := "oil_pit" if has_oil_pit else "ditch" if has_ditch else ""
	if key.is_empty():
		return null
	if not _defense_work_texture_cache.has(key):
		var path := "res://assets/walls/%s.png" % key
		_defense_work_texture_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _defense_work_texture_cache[key]
