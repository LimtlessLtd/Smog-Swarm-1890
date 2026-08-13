class_name NoiseVisuals
extends RefCounted

## Shared placeholder color/intensity lookup for the Threat Meter — same
## "*Visuals.gd" convention `BuildingVisuals`/
## `TerrainVisuals`/`FogVisuals`/`WallVisuals` already established, so a
## color choice doesn't silently drift between the Threat Meter's two
## surfaces: `StrategicOverlayManager`'s world-view markers and
## `MinimapView`'s own minimap copy. Each caller supplies its own min/max
## marker radius (world-space hex-sized units on the Strategic view vs.
## small fixed minimap pixels) — only the color and the 0.0-1.0 intensity
## curve are shared.

## Display-only normalization ceiling — deliberately NOT the same value as
## `HordeManager.ATTRACTION_THRESHOLD` (that's the gameplay threshold a
## horde actually reacts to; this is just "what noise level reads as
## visually maxed-out"), though roughly in the same ballpark by design (a
## couple of stacked industrial buildings, or one doubled by night).
const VISUALIZATION_MAX_NOISE: float = 12.0

const COLOR_LOW: Color = Color(0.95, 0.75, 0.1, 0.5)   ## Amber, translucent — a faint threat.
const COLOR_HIGH: Color = Color(0.85, 0.15, 0.1, 0.8)  ## Red, more opaque — a serious one.

static func intensity(noise: float) -> float:
	return clampf(noise / VISUALIZATION_MAX_NOISE, 0.0, 1.0)

static func color(noise: float) -> Color:
	return COLOR_LOW.lerp(COLOR_HIGH, intensity(noise))

static func radius(noise: float, min_radius: float, max_radius: float) -> float:
	return lerpf(min_radius, max_radius, intensity(noise))
