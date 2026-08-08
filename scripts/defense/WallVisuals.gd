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
