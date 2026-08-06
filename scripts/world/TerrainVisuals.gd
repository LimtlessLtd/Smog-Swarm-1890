class_name TerrainVisuals
extends RefCounted

## Shared placeholder biome/soil -> Color lookup, extracted from
## HexCellView (its own doc comment already called this the thing to "swap
## ... for a tile-texture lookup once [real art assets] do") so a second
## renderer can agree with it instead of drifting into a copy — same role
## BuildingVisuals.category_color()/FogVisuals.tint_color() already play for
## building/fog colors. TacticalHexView never needed this split (it
## composes a real HexCellView for its own ground rather than redrawing
## biome color itself), but Phase 6.1's minimap does: it draws hex terrain
## at a scale far too small to spawn a full HexCellView per tile.

static func biome_color(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility) -> Color:
	match biome:
		GameEnums.BiomeType.URBAN:
			return Color(0.42, 0.38, 0.35)
		GameEnums.BiomeType.INDUSTRIAL:
			return Color(0.25, 0.22, 0.22)
		GameEnums.BiomeType.HIGHLAND:
			return Color(0.48, 0.46, 0.38)
		GameEnums.BiomeType.WATERWAY:
			return Color(0.29, 0.46, 0.63)
		GameEnums.BiomeType.WETLAND:
			return Color(0.33, 0.40, 0.28)
		GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND:
			return soil_color(soil)
		_:
			return Color(0.5, 0.5, 0.5)

static func soil_color(soil: GameEnums.SoilFertility) -> Color:
	match soil:
		GameEnums.SoilFertility.LUSH:
			return Color(0.36, 0.56, 0.27)
		GameEnums.SoilFertility.POOR:
			return Color(0.55, 0.52, 0.35)
		GameEnums.SoilFertility.DESOLATE:
			return Color(0.35, 0.32, 0.30)
		_:
			return Color(0.5, 0.5, 0.5)
