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
## water, city streets, industrial ground). Bumped ~5x (Phase 2.5.6) from
## the original 14/6/8/10 alongside HexCoord.HEX_SIZE's 8x increase — a flat
## per-hex count spread over the new, much larger _SCATTER_RADIUS would
## otherwise look emptied-out (area grows with radius squared, so an
## unchanged count would sit at ~1/64th its old density). Not a full
## area-matched rescale (that would mean several hundred props per hex) —
## this is still a placeholder abstraction, not a literal tree census, and
## a smaller bump keeps the per-hex Polygon2D node count reasonable across
## the up-to-7 hexes LocalDetailManager can hydrate at once. Exact numbers
## are a balancing pass like every other constant here, not an architecture
## decision.
const _PROP_COUNT_BY_BIOME: Dictionary = {
	GameEnums.BiomeType.MOORLAND: 70,
	GameEnums.BiomeType.FARMLAND: 30,   ## Farmland is tilled — sparser than open moor.
	GameEnums.BiomeType.HIGHLAND: 40,
	GameEnums.BiomeType.WETLAND: 50,
	GameEnums.BiomeType.URBAN: 0,
	GameEnums.BiomeType.INDUSTRIAL: 0,
	GameEnums.BiomeType.WATERWAY: 0,
}

const _SCATTER_RADIUS: float = HexCoord.HEX_SIZE * 0.85  ## Stay inside the hex's own outline. Scales automatically with Phase 2.5.6's HEX_SIZE increase.

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
