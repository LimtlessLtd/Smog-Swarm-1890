class_name ZombieVisuals
extends RefCounted

## Shared lazy-load/cache/`ResourceLoader.exists()`-gated lookup for zombie
## figure art — same convention `UnitVisuals`/`BuildingVisuals`/`TerrainVisuals`
## already established. The one real difference from `UnitVisuals`: a
## `Horde` has no "type" the way a `UnitInstance` does (`GameEnums.UnitType`
## has 18 values; there's nothing equivalent for zombies) — every figure in
## every horde is mechanically identical. `VARIANT_COUNT` small recolors/
## poses exist purely for visual variety at HIGH fidelity's individual-figure
## rendering (a wall of visually-identical clones reads worse than a mix),
## chosen deterministically per figure (index-seeded, same "same figure
## count always scatters into the same shape" determinism
## `TacticalEntityLayer._scatter_offset()` already uses) rather than randomly
## — a horde's own rendered look shouldn't flicker between redraws.

const VARIANT_COUNT: int = 3

static var _texture_cache: Dictionary = {}  # int (variant, already wrapped 0..VARIANT_COUNT-1) -> Texture2D (nullable)

static func zombie_texture(variant_seed: int) -> Texture2D:
	var variant := ((variant_seed % VARIANT_COUNT) + VARIANT_COUNT) % VARIANT_COUNT  # Always non-negative regardless of variant_seed's sign.
	if not _texture_cache.has(variant):
		_texture_cache[variant] = _load_texture(variant)
	return _texture_cache[variant]

static func _load_texture(variant: int) -> Texture2D:
	var path := "res://assets/zombies/zombie_%d.png" % variant
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
