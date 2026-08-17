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

static var _unseen_material: ShaderMaterial
static var _explored_material: ShaderMaterial

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

static func _make_material(fog_mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/fog_overlay.gdshader")
	material.set_shader_parameter("fog_mode", fog_mode)
	return material
