class_name LocalDetailGenerator
extends RefCounted

## Procedural prop scatter for one hex's Tactical view. Purely
## cosmetic dressing — biome/soil/district data (HexMapGenerator's job) is
## untouched by this. Deterministic and coordinate-seeded rather than
## world-seeded like HexMapGenerator's FastNoiseLite passes, because this
## only ever needs to reproduce ONE hex's scatter on demand (whenever that
## hex is hydrated into view), never the whole map at once — a RandomNumberGenerator
## seeded from the hex's own coord is enough, and cheaper to call per-hex than
## sampling a shared noise field would be.

## Props per hex by biome; 0 means that biome gets no scatter at all (open
## water, city streets, industrial ground). Bumped ~5x from
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
	GameEnums.BiomeType.WOODLAND: 110,  ## Granularity pass — denser than open Moorland; this IS the biome that used to be Moorland's own tree-heavy end before the split.
	GameEnums.BiomeType.HEATHLAND: 55,  ## Low shrub cover — denser than tilled Farmland, sparser than a full forest canopy.
}

const _SCATTER_RADIUS: float = HexCoord.HEX_SIZE * 0.85  ## Stay inside the hex's own outline. Scales automatically with HexCoord.HEX_SIZE.

## Real bug fixed (player report: terrain props "that have a right way up
## (like trees)... are placed in a random rotation, meaning many trees are
## upside down"). Every currently-authored prop texture (`PropVisuals`,
## assets/props/*.png) is a real illustrated thing with a natural "up" — a
## tree/bush/reed's canopy-over-roots growth direction, confirmed directly
## against tree.png's own art (a canopy spreading from a trunk/root base) —
## not a rotation-agnostic blob. Only a rock genuinely has no meaningful
## up/down in nature. A full `0..TAU` spin used to apply uniformly to every
## prop type regardless, so roughly half of every oriented prop rendered
## visibly wrong. `_FREE_ROTATION_PROP_TYPES` names the type(s) still
## allowed the full random spin; everything else gets a small natural-sway
## jitter instead of an actual orientation change.
const _FREE_ROTATION_PROP_TYPES: Array[GameEnums.PropType] = [GameEnums.PropType.ROCK]
const _ORIENTED_PROP_JITTER_RAD: float = 0.349066  ## ~20 degrees either way — real trees/bushes/reeds don't grow perfectly vertical either, but this keeps every one of them reading as clearly upright rather than a true random orientation.

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
		prop.rotation = rng.randf_range(0.0, TAU) if _FREE_ROTATION_PROP_TYPES.has(prop.prop_type) else rng.randf_range(-_ORIENTED_PROP_JITTER_RAD, _ORIENTED_PROP_JITTER_RAD)
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
		GameEnums.BiomeType.WOODLAND:
			return GameEnums.PropType.TREE if rng.randf() < 0.9 else GameEnums.PropType.BUSH  ## Granularity pass — heavier tree bias than the general mix below; this is specifically forest cover.
		GameEnums.BiomeType.HEATHLAND:
			return GameEnums.PropType.BUSH if rng.randf() < 0.85 else GameEnums.PropType.TREE  ## Granularity pass — heather/gorse scrub reads as low bushes, not trees.
		_:
			return GameEnums.PropType.TREE if rng.randf() < 0.75 else GameEnums.PropType.BUSH
