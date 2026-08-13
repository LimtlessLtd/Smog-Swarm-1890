class_name ZoneOfControlVisuals
extends RefCounted

## Shared color/shape lookup for Zone of Control markers. "There should be
## UI options to display zones of control on the hex tile map and the
## tactical view too" (user request). Same "*Visuals.gd" convention every
## other lookup class here follows, shared between
## `StrategicOverlayManager`'s world-view markers and `TacticalHexView`'s
## own copy so a color choice can't drift between the two.
##
## Military and Civilian ZoC get genuinely different SHAPES, not just
## colors (this project's own "never color alone" accessibility rule):
## Military renders as a hex-bordered OUTLINE ("a patrol perimeter, not a
## filled zone" — it's an area of presence/vision/supply, not ownership),
## Civilian as a translucent FILL covering the whole hex ("this hex belongs
## to the settlement"). A hex under both draws both at once — an outline
## and a fill don't visually conflict, no special-cased "both" look needed.

const MILITARY_OUTLINE_COLOR: Color = Color(0.55, 0.75, 0.35, 0.9)  ## Olive/khaki-green — martial, distinct from every other marker's own hue.
const MILITARY_OUTLINE_WIDTH: float = 3.0
const CIVILIAN_FILL_COLOR: Color = Color(0.35, 0.55, 0.85, 0.22)  ## Translucent civic blue.
