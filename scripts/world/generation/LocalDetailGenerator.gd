class_name LocalDetailGenerator
extends RefCounted

## Procedural prop scatter for one hex's Tactical view (Phase 2.5). Purely
## cosmetic dressing — biome/soil/district data (HexMapGenerator's job) is
## untouched by this. Deterministic and coordinate-seeded rather than
## world-seeded like HexMapGenerator's FastNoiseLite passes, because this
## only ever needs to reproduce ONE hex's scatter on demand (whenever that
## hex is hydrated into view), never the whole map at once — a RandomNumberGenerator
## seeded from the hex's own coord is enough, and cheaper to call per-hex than
## sampling a shared noise field would be.

## Props per hex by biome; 0 means that biome gets no scatter at all (open
## water, city streets, industrial ground).
const _PROP_COUNT_BY_BIOME: Dictionary = {
	GameEnums.BiomeType.MOORLAND: 14,
	GameEnums.BiomeType.FARMLAND: 6,   ## Farmland is tilled — sparser than open moor.
	GameEnums.BiomeType.HIGHLAND: 8,
	GameEnums.BiomeType.WETLAND: 10,
	GameEnums.BiomeType.URBAN: 0,
	GameEnums.BiomeType.INDUSTRIAL: 0,
	GameEnums.BiomeType.WATERWAY: 0,
}

const _SCATTER_RADIUS: float = HexCoord.HEX_SIZE * 0.85  ## Stay inside the hex's own outline.

static func generate(cell: HexCell) -> Array[PropInstance]:
	var props: Array[PropInstance] = []
	var count: int = _PROP_COUNT_BY_BIOME.get(cell.biome_type, 0)
	if count <= 0:
		return props

	var rng := RandomNumberGenerator.new()
	rng.seed = _hex_seed(cell.coord)

	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.0, _SCATTER_RADIUS)
		var local_position := Vector2(cos(angle), sin(angle)) * radius
		var prop := PropInstance.new(_prop_type_for_biome(cell.biome_type, rng), local_position)
		prop.rotation = rng.randf_range(0.0, TAU)
		prop.scale = rng.randf_range(0.8, 1.3)
		props.append(prop)

	return props

## Order-independent hash of the axial coord — same hex always scatters the
## same props, regardless of generation/hydration order.
static func _hex_seed(coord: Vector2i) -> int:
	return int(coord.x) * 73856093 ^ int(coord.y) * 19349663

static func _prop_type_for_biome(biome: GameEnums.BiomeType, rng: RandomNumberGenerator) -> GameEnums.PropType:
	match biome:
		GameEnums.BiomeType.WETLAND:
			return GameEnums.PropType.REED
		GameEnums.BiomeType.HIGHLAND:
			return GameEnums.PropType.ROCK
		_:
			return GameEnums.PropType.TREE if rng.randf() < 0.75 else GameEnums.PropType.BUSH
