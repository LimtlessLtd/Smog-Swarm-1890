class_name FogVisuals
extends RefCounted

## Shared UNSEEN/EXPLORED/VISIBLE -> Node2D.modulate lookup, so the
## Strategic view (HexCellView) and the Tactical view (TacticalHexView)
## render fog state identically instead of two copies drifting apart —
## same role BuildingVisuals.category_color() plays for building colors.
##
## overlay_material() adds a second, ANIMATED signal on top of the plain
## modulate tint above — "fog of war should be cloudy misty animations
## moving over an area... obscured tiles need to have visibly different
## overlay animations" (user request; a flat modulate multiply can't animate
## on its own). Backed by assets/shaders/fog_overlay.gdshader's `fog_mode`
## uniform (0 = UNSEEN dense mist, 1 = EXPLORED sparse haze) — see that
## file's own doc comment for the visual distinction. Exactly two
## ShaderMaterial instances exist for the whole game, cached here and reused
## by every tile (both HexCellView and TacticalHexView add the SAME material
## resource to their own overlay Polygon2D — a shared ShaderMaterial's
## uniforms/TIME apply identically to every CanvasItem it's assigned to, so
## this costs nothing per-hex beyond the one extra draw call).

## z_index every terrain fog overlay is pinned to, ABOVE TerrainMeshView's
## GROUND_Z_INDEX and below the 0-and-up entity band. Absolute, not relative:
## HexCellView sits at -3 and its overlay has to escape that subtree's depth to
## cover a mesh that is not its child.
##
## This band exists because terrain stopped being per-hex. While each hex drew
## its own ground, fog was just `modulate` on the node that owned it; a single
## world-wide mesh has no per-hex node to tint, so the fog polygon has to be
## lifted over it instead. Anything inserted between this and GROUND_Z_INDEX
## would render as un-foggable terrain.
const TERRAIN_OVERLAY_Z_INDEX: int = -1

## Alpha multiplier for SeaView's haze, i.e. the sea reads at roughly 60% of
## its own colour through it. "the sea should be blue and be visible through the
## fog (like 60% opacity)" (user, 2026-08-18) — read as how much of the SEA
## shows, so the haze takes the remainder. Flip this one number if the intent
## was the other way round.
const SEA_HAZE_OPACITY: float = 0.4

static var _unseen_material: ShaderMaterial
static var _explored_material: ShaderMaterial
static var _sea_material: ShaderMaterial

static func tint_color(state: GameEnums.FogState) -> Color:
	match state:
		GameEnums.FogState.UNSEEN:
			return Color(0.0, 0.0, 0.0, 1.0)     ## Blank darkness — hides the tile entirely.
		GameEnums.FogState.EXPLORED:
			return Color(0.45, 0.45, 0.45, 1.0)  ## Remembered, dimmed — no current intel on movement.
		_:  # VISIBLE
			return Color(1.0, 1.0, 1.0, 1.0)     ## Untinted — full real-time information.

## null for VISIBLE — callers hide/skip their own overlay node in that case,
## same "null means don't draw" contract BuildingVisuals/TerrainVisuals use
## for unauthored art.
static func overlay_material(state: GameEnums.FogState) -> ShaderMaterial:
	match state:
		GameEnums.FogState.UNSEEN:
			if not _unseen_material:
				_unseen_material = _make_material(0)
			return _unseen_material
		GameEnums.FogState.EXPLORED:
			if not _explored_material:
				_explored_material = _make_material(1)
			return _explored_material
		_:  # VISIBLE
			return null

## The UNSEEN look at SEA_HAZE_OPACITY, for SeaView's single map-wide haze.
## A third shared instance rather than a per-caller material: like the other
## two, one ShaderMaterial is reused by every CanvasItem it is assigned to.
static func sea_overlay_material() -> ShaderMaterial:
	if not _sea_material:
		_sea_material = _make_material(0)
		_sea_material.set_shader_parameter("opacity", SEA_HAZE_OPACITY)
	return _sea_material

static func _make_material(fog_mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/fog_overlay.gdshader")
	material.set_shader_parameter("fog_mode", fog_mode)
	return material
