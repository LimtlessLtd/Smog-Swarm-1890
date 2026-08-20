class_name TerrainVisuals
extends RefCounted

## Shared placeholder biome/soil -> Color lookup, extracted from
## HexCellView so a second renderer can agree with it instead of drifting
## into a copy — same role BuildingVisuals.category_color()/
## FogVisuals.tint_color() play for building/fog colors. TacticalHexView
## never needed this split (it composes a real HexCellView for its own
## ground rather than redrawing biome color itself), but MinimapView does:
## it draws hex terrain at a scale far too small to spawn a full
## HexCellView per tile.
##
## terrain_texture() below is additive over biome_color()/soil_color(), not
## a replacement. MinimapView keeps calling the color functions directly,
## unchanged: its dots are 2-3 minimap-pixels, far too small for texture
## detail to read at all. terrain_texture() is the seam HexCellView
## (Strategic + Tactical alike, same tiled draw path) reads instead.

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
		GameEnums.BiomeType.OCEAN:
			## Still deeper than WATERWAY's river-blue — open sea, not a fordable
			## river — but lifted from (0.10, 0.18, 0.28), which was chosen when
			## nothing actually drew the sea and it only ever showed as a minimap
			## pixel. SeaView now paints it full-screen under a haze that mixes
			## ~40% grey into it, and at the old value that composited to a muddy
			## near-grey rather than "the sea should be blue" (user, 2026-08-18).
			return Color(0.16, 0.30, 0.46)
		GameEnums.BiomeType.WOODLAND:
			return Color(0.20, 0.34, 0.16)  ## Deep forest canopy green, distinctly darker/denser than Moorland's open grass.
		GameEnums.BiomeType.HEATHLAND:
			return Color(0.44, 0.34, 0.42)  ## Heather/gorse purple-brown, distinct from Moorland's green and Farmland's soil-driven palette.
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
## than throwing — this is what lets art land one file at a time with zero
## code changes needed in between: HexCellView already falls back to
## biome_color() whenever this returns null.
static var _texture_cache: Dictionary = {}  # String key -> Texture2D (nullable)

## `terrain_feature` — optional, defaults to NONE so every pre-existing
## caller keeps its old behavior. Only WATERWAY branches on it: a River and
## a Canal used to resolve to the exact same "waterway" texture despite
## HexCell.terrain_feature already distinguishing them (RIVER vs CANAL) —
## a Canal reads as visibly man-made (straight banks/towpath,
## assets/terrain/canal.svg) instead of identical to a natural river.
static func terrain_texture(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility, terrain_feature: GameEnums.TerrainFeature = GameEnums.TerrainFeature.NONE) -> Texture2D:
	var key := _texture_key(biome, soil, terrain_feature)
	if not _texture_cache.has(key):
		_texture_cache[key] = _load_texture(key)
	return _texture_cache[key]

## True where terrain_texture()/biome_color() actually answer differently for
## different soil ratings. FARMLAND and MOORLAND resolve to a per-soil SVG
## (`farmland_lush` etc.) and to soil_color(); every other biome ignores the
## argument entirely.
##
## Lives here rather than in the caller because _texture_key() below is what
## makes it true — a renderer asking "does soil change what I draw?" must not
## answer by restating that match statement somewhere else, or the two drift
## the first time a biome gains soil art.
static func varies_by_soil(biome: GameEnums.BiomeType) -> bool:
	return biome == GameEnums.BiomeType.FARMLAND or biome == GameEnums.BiomeType.MOORLAND


## Matches assets/terrain/<key>.svg exactly — see that folder's own file list.
static func _texture_key(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility, terrain_feature: GameEnums.TerrainFeature = GameEnums.TerrainFeature.NONE) -> String:
	match biome:
		GameEnums.BiomeType.URBAN:
			return "urban"
		GameEnums.BiomeType.INDUSTRIAL:
			return "industrial"
		GameEnums.BiomeType.HIGHLAND:
			return "highland"
		GameEnums.BiomeType.WATERWAY:
			return "canal" if terrain_feature == GameEnums.TerrainFeature.CANAL else "waterway"
		GameEnums.BiomeType.WETLAND:
			return "wetland"
		GameEnums.BiomeType.OCEAN:
			return "ocean"  ## No assets/terrain/ocean.svg authored — falls back to biome_color()'s flat OCEAN color, same "art lands incrementally" contract every other biome follows. Explicit case so it does NOT fall into the "_:" MOORLAND bucket, which WOULD resolve to a real, wrong texture.
		GameEnums.BiomeType.WOODLAND:
			return "woodland"
		GameEnums.BiomeType.HEATHLAND:
			return "heathland"
		GameEnums.BiomeType.FARMLAND:
			return "farmland_%s" % _soil_key(soil)
		_:  # MOORLAND
			return "moorland_%s" % _soil_key(soil)

## NOT_ARABLE never actually reaches here — FARMLAND/MOORLAND never carry
## that soil rating (see HexMapGenerator) — so it falls into the same
## bucket as POOR rather than needing its own art.
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
