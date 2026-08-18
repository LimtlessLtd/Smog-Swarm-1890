class_name SubHexSoilQuery
extends RefCounted

## Sub-Hex Mechanical Layer Phase 3 (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — soil fertility at real 30m sub-hex resolution, the specific gap
## SubHexTerrainQuery's own doc comment flagged as "Phase 3's job":
## RealTerrainSampler.sample_at() has no soil_fertility field at all —
## HexMapGenerator derives it separately per MACRO hex (a biome match plus a
## seeded noise pass, _apply_soil_noise()). This class reruns that exact
## derivation at sub-hex granularity: SubHexTerrainQuery's own per-sub-cell
## biome_type (itself finer than a macro hex's single majority-voted
## biome_type where a real fine tile is baked) drives the same biome match
## table _apply_real_terrain() uses, and MOORLAND/FARMLAND sub-cells run the
## identical noise field (HexMapGenerator.SOIL_NOISE_SEED/FREQUENCY/
## thresholds — shared constants, never redeclared here) evaluated at the
## sub-cell's own CONTINUOUS fractional axial position
## (HexCoord.world_to_axial_fractional()) instead of the whole hex's single
## integer (q, r) — real intra-hex variation instead of one flat value
## across an entire ~5km hex.
##
## Falls back to `fallback` (the caller-supplied macro HexCell.soil_fertility)
## when SubHexTerrainQuery returns {} for this position (outside the baked
## corridor) — same "empty result -> fall back to flat default" contract
## every other class in this epic already follows.
##
## Known, disclosed gap: hand-placed GeographyFeature stamps
## (HexMapGenerator._apply_feature() — mountain ranges, named wetlands,
## farmland belts, industrial blight) aren't independently re-derivable
## here; this class only replicates _apply_real_terrain()'s BIOME-based
## match table, not the feature-stamp overrides layered on top of it in
## macro generation. Where a stamp's effect is already reflected in the
## real OSM-derived raster at that position — true for most hand-placed
## features, chosen to match real geography — this is a non-issue; a stamp
## that's a deliberate creative liberty beyond what the raster shows can
## diverge from the macro hex's own stamped rating. Accepted for the same
## reason SubHexTerrainQuery's own Phase 1a aliasing disclosure was: no
## consumer needs byte-identical macro/sub-hex agreement, only a real,
## directionally-correct improvement over "the whole hex has one value."

static var _noise: FastNoiseLite

## `local_position` is an offset from `hex_coord`'s own center — the same
## field BuildingInstance already carries (previously cosmetic-only for
## this purpose; see BuildingInstance.get_effective_output()).
static func soil_fertility_at(hex_coord: Vector2i, local_position: Vector2, fallback: GameEnums.SoilFertility) -> GameEnums.SoilFertility:
	var world_pos := HexCoord.axial_to_world(hex_coord) + local_position
	var sample := SubHexTerrainQuery.sample_at_world_within(hex_coord, world_pos)
	if sample.is_empty():
		return fallback
	return soil_for_biome_at(sample.get("biome_type", GameEnums.BiomeType.MOORLAND), world_pos)


## The same rule soil_fertility_at() applies, for a caller that ALREADY knows
## which biome is at `world_pos` and so does not need the terrain lookup that
## resolves it. TerrainMeshView's triangles carry their own biome, and routing
## them back through soil_fertility_at() would re-derive from the raster the
## very thing the vector mesh already states — and would disagree with it
## wherever the two representations differ, which is the whole point of the
## vector terrain epic.
static func soil_for_biome_at(biome: GameEnums.BiomeType, world_pos: Vector2) -> GameEnums.SoilFertility:
	match biome:
		GameEnums.BiomeType.URBAN:
			return GameEnums.SoilFertility.NOT_ARABLE
		GameEnums.BiomeType.INDUSTRIAL:
			return GameEnums.SoilFertility.DESOLATE
		GameEnums.BiomeType.HIGHLAND:
			return GameEnums.SoilFertility.POOR
		GameEnums.BiomeType.WETLAND:
			return GameEnums.SoilFertility.DESOLATE
		GameEnums.BiomeType.WATERWAY:
			return GameEnums.SoilFertility.POOR
		GameEnums.BiomeType.WOODLAND, GameEnums.BiomeType.HEATHLAND:
			return GameEnums.SoilFertility.NOT_ARABLE
		GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND:
			return _noise_fertility(world_pos)
		_:  # Matches HexMapGenerator._apply_real_terrain()'s own catch-all (OCEAN, or any future biome not listed above) — fixed POOR, never noise-varied.
			return GameEnums.SoilFertility.POOR

static func _noise_fertility(world_pos: Vector2) -> GameEnums.SoilFertility:
	if not _noise:
		_noise = FastNoiseLite.new()
		_noise.seed = HexMapGenerator.SOIL_NOISE_SEED
		_noise.frequency = HexMapGenerator.SOIL_NOISE_FREQUENCY
		_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	var frac := HexCoord.world_to_axial_fractional(world_pos)
	var n := _noise.get_noise_2d(frac.x, frac.y)
	if n > HexMapGenerator.SOIL_NOISE_LUSH_THRESHOLD:
		return GameEnums.SoilFertility.LUSH
	elif n < HexMapGenerator.SOIL_NOISE_DESOLATE_THRESHOLD:
		return GameEnums.SoilFertility.DESOLATE
	return GameEnums.SoilFertility.POOR
