class_name ObstacleRadii
extends RefCounted

## Design doc, user request (local obstacle avoidance for continuous
## movement) — neither `PropInstance` (scripts/world/data/PropInstance.gd)
## nor `BuildingInstance` (scripts/buildings/data/BuildingInstance.gd) has
## a collision-radius field of its own (props are placed for pure visual
## scatter, buildings for placement/ZoC/combat — neither needed a physical
## footprint before now). Same "shared lookup, swappable later" convention
## as `BuildingVisuals`/`TerrainVisuals`/`FogVisuals` — placeholder
## balancing numbers, not an architecture decision, same framing as every
## other constant table in this project. Consumed by `MovementStepper`'s
## callers (`UnitOrderController`/`HordeManager`) when gathering obstacles
## for `steer_around_obstacles()`.

## Rough clearance radius per prop type, loosely matching
## `TacticalHexView._prop_polygon()`'s own hardcoded per-species vertex
## sizes (roughly 8-12 world units before a prop's own `scale`) with extra
## margin so a walking entity visibly detours rather than clipping the
## silhouette.
const PROP_RADIUS: Dictionary = {
	GameEnums.PropType.TREE: 24.0,
	GameEnums.PropType.BUSH: 16.0,
	GameEnums.PropType.ROCK: 18.0,
	GameEnums.PropType.REED: 10.0,  ## Reeds are sparse/thin — barely an obstacle, mostly a visual cue for wetland fringe.
}

## Bounding circle of `TacticalHexView.BUILDING_HALF_SIZE`'s real-scale
## building box (half-extent 5.128 -> center-to-corner half-diagonal
## ~7.25), rounded up for clearance. **This constant had silently drifted
## out of sync with the real box size across TWO prior building-box resizes
## before this one (10 -> 35 -> 70, this comment still describing the
## original 10) — re-synced now, not just for this pass's own resize.**
## One flat radius for every building type — today's placement footprint
## doesn't vary by category, so neither does this.
const BUILDING_RADIUS: float = 8.0

## `.get(prop_type, ...)` with a sane fallback so a future GameEnums.PropType
## addition without a matching entry here degrades to "treated as an
## obstacle" rather than silently invisible to steering.
static func for_prop(prop_type: GameEnums.PropType) -> float:
	return PROP_RADIUS.get(prop_type, 15.0)
