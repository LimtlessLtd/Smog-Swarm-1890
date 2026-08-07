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
##
## "Real art" landed: terrain_texture() below is exactly the swap the doc
## comment above was pointing at — but ADDITIVE, not a replacement.
## biome_color()/soil_color() are untouched and MinimapView keeps calling
## them directly, unchanged: its dots are 2-3 minimap-pixels, far too small
## for texture detail to read at all. terrain_texture() is the new seam
## HexCellView (Strategic + Tactical alike, same tiled draw path) reads instead.

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

## Lazily-loaded, cached (same "build once, cache" convention as
## BuildingCatalog/UnitCatalog's _ensure_built()) — the real texture for a
## biome/soil combination, or null if no SVG has been authored yet at
## assets/terrain/<key>.svg. ResourceLoader.exists() before load() means an
## unauthored biome fails cleanly to null (no console error spam) rather
## than throwing — this is what let art land one file at a time with zero
## code changes needed in between: HexCellView already falls back to
## biome_color() whenever this returns null.
static var _texture_cache: Dictionary = {}  # String key -> Texture2D (nullable)

static func terrain_texture(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility) -> Texture2D:
	var key := _texture_key(biome, soil)
	if not _texture_cache.has(key):
		_texture_cache[key] = _load_texture(key)
	return _texture_cache[key]

## Matches assets/terrain/<key>.svg exactly — see that folder's own file list.
static func _texture_key(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility) -> String:
	match biome:
		GameEnums.BiomeType.URBAN:
			return "urban"
		GameEnums.BiomeType.INDUSTRIAL:
			return "industrial"
		GameEnums.BiomeType.HIGHLAND:
			return "highland"
		GameEnums.BiomeType.WATERWAY:
			return "waterway"
		GameEnums.BiomeType.WETLAND:
			return "wetland"
		GameEnums.BiomeType.FARMLAND:
			return "farmland_%s" % _soil_key(soil)
		_:  # MOORLAND
			return "moorland_%s" % _soil_key(soil)

## NOT_ARABLE never actually reaches here — FARMLAND/MOORLAND never carry
## that soil rating (see HexMapGenerator) — so it deliberately falls into
## the same bucket as POOR rather than needing its own art.
static func _soil_key(soil: GameEnums.SoilFertility) -> String:
	match soil:
		GameEnums.SoilFertility.LUSH:
			return "lush"
		GameEnums.SoilFertility.DESOLATE:
			return "desolate"
		_:
			return "poor"

static func _load_texture(key: String) -> Texture2D:
	var path := "res://assets/terrain/%s.svg" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
