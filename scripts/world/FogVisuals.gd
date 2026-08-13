class_name FogVisuals
extends RefCounted

## Shared UNSEEN/EXPLORED/VISIBLE -> Node2D.modulate lookup, so the
## Strategic view (HexCellView) and the Tactical view (TacticalHexView)
## render fog state identically instead of two copies drifting apart —
## same role BuildingVisuals.category_color() plays for building colors.

static func tint_color(state: GameEnums.FogState) -> Color:
	match state:
		GameEnums.FogState.UNSEEN:
			return Color(0.0, 0.0, 0.0, 1.0)     ## Blank darkness — hides the tile entirely.
		GameEnums.FogState.EXPLORED:
			return Color(0.45, 0.45, 0.45, 1.0)  ## Remembered, dimmed — no current intel on movement.
		_:  # VISIBLE
			return Color(1.0, 1.0, 1.0, 1.0)     ## Untinted — full real-time information.
