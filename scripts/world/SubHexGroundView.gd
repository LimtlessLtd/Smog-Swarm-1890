class_name SubHexGroundView
extends Node2D

## Real sub-hex ground rendering for Tactical zoom (replaces the flat,
## uniform HexCellView ground tile TacticalHexView used to compose).
## Samples an N x N real-world grid across the hex's own footprint
## (RealTerrainSampler — OpenStreetMap land-cover + AWS/Mapzen elevation,
## baked offline by tools/geo_bake/bake_landcover.py) and composites the
## SAME 11 hand-authored terrain SVGs TerrainVisuals already provides —
## real data drives WHERE each already-styled texture appears within a
## hex, not new photorealistic art, keeping this visually consistent
## with the game's established illustrated look. This is the actual,
## visible answer to "move away from hex-tile-locked mechanics": a
## single hex can now show a hillside corner, a river cutting through,
## and open farmland simultaneously instead of one uniform tile.
##
## Deliberately uses Sprite2D (NOT Polygon2D) per sub-cell — sidesteps
## BOTH of this project's already-documented Polygon2D UV pitfalls by
## construction, not by care: (1) a hex-fan Polygon2D with an explicit
## per-corner UV array only samples a HANDFUL of sparse texture points
## and interpolates between them, it doesn't rasterize/warp a full image
## into the polygon shape (this is why Strategic's old "paint the whole
## texture once" ICON mode never worked, see HexCellView's own doc
## comment); (2) Polygon2D.uv coordinates are in the texture's PIXEL
## space, not normalized 0..1 (the building-sprite bug, see
## TacticalHexView.quad_uv()'s own doc comment). Sprite2D with
## region_enabled/region_rect does genuine GPU rect-sampling instead of
## either — it isn't a Polygon2D at all, so neither bug class applies.
##
## Real data drives PLACEMENT only; soil-fertility color variance (lush/
## poor/desolate) is inherited from the whole hex's own already-computed
## HexCell.soil_fertility rather than baked at sub-hex resolution — a
## deliberate, disclosed simplification (soil-tint granularity was never
## the actual "move away from hex-tile mechanics" ask; real biome/water/
## elevation placement is).

const _GRID_N: int = 7  ## odd, so there's a true center sample aligned with the hex's own already-computed majority-vote biome_type — avoids a visible seam between Strategic's flat tile and this grid's own center.
const _GRID_SPAN: float = HexCoord.HEX_SIZE * 1.6  ## matches RealTerrainSampler.sample_grid()'s own span so sub-cells tile edge to edge with zero gap/overlap ambiguity.

func setup(cell: HexCell) -> void:
	for child in get_children():
		child.queue_free()

	if not RealTerrainSampler.is_available():
		_build_fallback(cell)
		return

	var samples := RealTerrainSampler.sample_grid(cell.coord, _GRID_N)
	if samples.is_empty() or samples[0].is_empty():
		_build_fallback(cell)
		return

	var cell_size := _GRID_SPAN / float(_GRID_N)
	var start := -_GRID_SPAN * 0.5 + cell_size * 0.5
	var distinct_textures: Dictionary = {}
	for row in range(_GRID_N):
		for col in range(_GRID_N):
			var sample: Dictionary = samples[row * _GRID_N + col]
			if sample.is_empty():
				continue
			var biome: GameEnums.BiomeType = sample["biome_type"]
			var soil := cell.soil_fertility if (biome == GameEnums.BiomeType.FARMLAND or biome == GameEnums.BiomeType.MOORLAND) else GameEnums.SoilFertility.NOT_ARABLE
			var texture := TerrainVisuals.terrain_texture(biome, soil)
			var sub_pos := Vector2(start + col * cell_size, start + row * cell_size)
			add_child(_build_sub_cell(texture, biome, soil, sub_pos, cell_size))
			if texture:
				distinct_textures[texture] = true
			else:
				distinct_textures[TerrainVisuals.biome_color(biome, soil)] = true

	# Fewer than 2 distinct textures across the whole grid (a hex that
	# real data classified as uniformly one biome) is a perfectly valid
	# outcome, not a bug — most hexes genuinely are one thing throughout.

func _build_sub_cell(texture: Texture2D, biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility, local_pos: Vector2, cell_size: float) -> Node2D:
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ZERO, texture.get_size())
		sprite.position = local_pos
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (cell_size / largest_dim)
		return sprite

	# No art authored yet for this biome/soil combination (e.g. OCEAN,
	# deliberately unauthored per TerrainVisuals' own doc comment) — same
	# flat-color fallback HexCellView already uses. Polygon2D, not
	# ColorRect — this whole scene lives under Node2D-space TacticalHexView
	# (positions/scale in world units), and ColorRect is a Control node,
	# a different tree entirely (caught by a real Godot --import compile
	# pass: "Cannot return value of type ColorRect because the function
	# return type is Node2D").
	var half := cell_size * 0.5
	var flat := Polygon2D.new()
	flat.color = TerrainVisuals.biome_color(biome, soil)
	flat.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	flat.position = local_pos
	return flat

## Graceful degradation if the bake hasn't been run/committed yet
## (RealTerrainSampler.is_available() == false) — exactly today's single
## flat-textured HexCellView, so a fresh clone without the (large,
## binary) baked terrain_data assets still renders a correct, if
## data-poor, Tactical view rather than an empty hex.
func _build_fallback(cell: HexCell) -> void:
	var ground := HexCellView.new()
	ground.setup(cell)
	add_child(ground)
