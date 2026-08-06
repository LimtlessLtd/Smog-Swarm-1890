class_name BuildingVisuals
extends RefCounted

## Shared placeholder color-by-category lookup for anything that draws a
## building as a plain colored shape before real art exists — TacticalHexView's
## close-up building boxes and StrategicOverlayManager's zoomed-out building
## icons both call this, so a given category reads as the same color in both
## views instead of two copy-pasted match blocks silently drifting apart.

static func category_color(category: GameEnums.BuildingCategory) -> Color:
	match category:
		GameEnums.BuildingCategory.HOUSING_CIVIL:
			return Color(0.55, 0.42, 0.30)
		GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
			return Color(0.35, 0.32, 0.34)
		GameEnums.BuildingCategory.AGRICULTURE:
			return Color(0.62, 0.55, 0.25)
		_:
			return Color(0.5, 0.5, 0.5)
