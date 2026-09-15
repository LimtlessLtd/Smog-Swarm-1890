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

## A whole Horde moves (and faces) as one entity — see
## TacticalEntityLayer._advance_facing(), called once per horde, not once
## per rendered figure — so `facing` here is the horde's shared facing, the
## same for every figure a given call site is drawing this frame.

static var _texture_cache: Dictionary = {}  # "<variant>_<Facing8>" -> Texture2D (nullable)

static func zombie_texture(variant_seed: int, facing: GameEnums.Facing8 = GameEnums.Facing8.S) -> Texture2D:
	var variant := ((variant_seed % VARIANT_COUNT) + VARIANT_COUNT) % VARIANT_COUNT  # Always non-negative regardless of variant_seed's sign.
	var cache_key := "%d_%d" % [variant, facing]
	if not _texture_cache.has(cache_key):
		_texture_cache[cache_key] = _load_texture(variant, facing)
	return _texture_cache[cache_key]

static var _facing_extent_cache: Dictionary = {}  # variant -> float

## Largest cropped dimension across all eight facings of a variant — the divisor
## to scale a zombie sprite by, rather than the current facing's own texture.
##
## Same reasoning as UnitVisuals.unit_facing_extent(): a tight crop (D88) is an
## AXIS-ALIGNED box, so it shrinks when an elongated model turns off-axis even
## though the model has not changed size. Milder here than on cavalry because no
## zombie is as long as a horse — measured 9.6-11.2% across the three variants
## against the Chasseur's 26% — but a horde is thousands of figures all turning,
## so a 10% per-figure pulse is the most visible place it could possibly land.
static func variant_facing_extent(variant_seed: int) -> float:
	var variant := ((variant_seed % VARIANT_COUNT) + VARIANT_COUNT) % VARIANT_COUNT
	if _facing_extent_cache.has(variant):
		return _facing_extent_cache[variant]
	var extent := 0.0
	for facing in GameEnums.Facing8.values():
		var texture := zombie_texture(variant, facing)
		if texture:
			extent = maxf(extent, maxf(texture.get_width(), texture.get_height()))
	_facing_extent_cache[variant] = extent
	return extent

static func _load_texture(variant: int, facing: GameEnums.Facing8) -> Texture2D:
	var directional_path := "res://assets/zombies/zombie_%d_%s.png" % [variant, FacingUtil.suffix(facing)]
	if ResourceLoader.exists(directional_path):
		return load(directional_path) as Texture2D
	var flat_path := "res://assets/zombies/zombie_%d.png" % variant  # Pre-directional single-facing art, if that's all that's been authored.
	if ResourceLoader.exists(flat_path):
		return load(flat_path) as Texture2D
	return null
