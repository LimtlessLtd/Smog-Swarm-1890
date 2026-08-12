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

## Bumped 7 -> 11 (user request, playtest round 4, #12: "tactical view
## terrain tiles are too big... make them smaller and more numerous per hex
## tile grid") — still odd, so there's a true center sample aligned with the
## hex's own already-computed majority-vote biome_type, same reasoning as
## before. More, smaller sub-cells also read as smoother/more "seamless"
## cross-biome blending at a glance even though _compute_blend() itself is
## unchanged — a finer grid just means each individual blend seam is
## shorter and less noticeable.
const _GRID_N: int = 11
const _GRID_SPAN: float = HexCoord.SUB_HEX_GRID_SPAN  ## Shared with RealTerrainSampler.sample_grid()'s own span (HexCoord.gd) — see that constant's own doc comment for why this exact value, and why a hex-shaped clip mask (below) is what actually keeps it from overhanging into neighboring hexes.

## Real cross-hex/cross-biome blending (user request: "changes in terrain
## and across hex borders should blend smoothly... some sort of gradient
## when moving from one type of terrain to another"). Loaded once, shared
## by every sub-cell's own ShaderMaterial instance (materials are cheap
## per-instance wrappers around one shared Shader resource, same "load
## once, cache" convention every *Visuals.gd lazy-loader already follows).
static var _blend_shader: Shader = null
static func _get_blend_shader() -> Shader:
	if _blend_shader == null:
		_blend_shader = load("res://assets/shaders/terrain_blend.gdshader") as Shader
	return _blend_shader

## Blend strength cap — a boundary cell always keeps at least this much of
## its OWN biome's identity even surrounded entirely by a different one, so
## a real transition zone reads as "this hex's edge fading into the next
## biome," not "which biome is this even." 0.6 chosen so a fully-surrounded
## boundary cell still visibly leans toward its own texture, not a 50/50 mush.
const _MAX_BLEND_WEIGHT: float = 0.6

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

	# **Real bug fix (playtest round 4, #9): "tactical view hexgrids have
	# overhanging terrain on each corner going over into neighbouring hex
	# tile grids"** — a SQUARE sample/render grid can never exactly match a
	# HEXAGONAL footprint; sized to fully cover the hex's own bounding box
	# (see HexCoord.SUB_HEX_GRID_SPAN's own doc comment), the square's own
	# four corners necessarily poke past the hex's real circumradius, into
	# whichever neighbor sits in that direction. `_hex_mask` below is a real
	# hex-shaped `Polygon2D` (HexCoord.corner_points() — the same six points
	# every hex-outline draw in this project already uses) with
	# `clip_children = CLIP_CHILDREN_ONLY`: every sub-cell sprite added as
	# ITS child (not this Node2D's directly) gets stencil-clipped to the
	# true hex shape, so whatever a corner sprite renders past the hex's own
	# edge is simply never drawn — the mask itself stays invisible
	# (CLIP_CHILDREN_ONLY, not _AND_DRAW), it's purely a stencil.
	var hex_mask := Polygon2D.new()
	hex_mask.polygon = HexCoord.corner_points(Vector2.ZERO)
	hex_mask.color = Color.WHITE  # Irrelevant to the final look — CLIP_CHILDREN_ONLY never actually draws this shape, only uses it as a stencil.
	hex_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(hex_mask)

	var cell_size := _GRID_SPAN / float(_GRID_N)
	var start := -_GRID_SPAN * 0.5 + cell_size * 0.5

	# First pass: resolve every sub-cell's own biome/soil/texture up front,
	# so the second pass can look up ANY of the 4-connected neighbors
	# (including ones not yet visited in row-major order) for blending.
	var biomes: Array = []       # GameEnums.BiomeType per index, or null if the sample was empty
	var textures: Array = []     # Texture2D per index, or null
	var soils: Array = []        # GameEnums.SoilFertility per index
	for i in range(_GRID_N * _GRID_N):
		var sample: Dictionary = samples[i]
		if sample.is_empty():
			biomes.append(null)
			textures.append(null)
			soils.append(GameEnums.SoilFertility.NOT_ARABLE)
			continue
		var biome: GameEnums.BiomeType = sample["biome_type"]
		var soil := cell.soil_fertility if (biome == GameEnums.BiomeType.FARMLAND or biome == GameEnums.BiomeType.MOORLAND) else GameEnums.SoilFertility.NOT_ARABLE
		biomes.append(biome)
		soils.append(soil)
		textures.append(TerrainVisuals.terrain_texture(biome, soil))

	var distinct_textures: Dictionary = {}
	for row in range(_GRID_N):
		for col in range(_GRID_N):
			var i := row * _GRID_N + col
			if biomes[i] == null:
				continue
			var biome: GameEnums.BiomeType = biomes[i]
			var soil: GameEnums.SoilFertility = soils[i]
			var texture: Texture2D = textures[i]
			var sub_pos := Vector2(start + col * cell_size, start + row * cell_size)
			var blend := _compute_blend(row, col, biomes, textures) if texture else {}
			hex_mask.add_child(_build_sub_cell(texture, biome, soil, sub_pos, cell_size, blend))
			if texture:
				distinct_textures[texture] = true
			else:
				distinct_textures[TerrainVisuals.biome_color(biome, soil)] = true

	# Fewer than 2 distinct textures across the whole grid (a hex that
	# real data classified as uniformly one biome) is a perfectly valid
	# outcome, not a bug — most hexes genuinely are one thing throughout.

## Examines this sub-cell's 4-connected neighbors (up/down/left/right
## within the same grid — cross-hex neighbors one grid-cell over aren't
## sampled here, so a blend never reaches past this hex's own footprint)
## and returns {} if none differ, or {secondary_texture, direction, weight}
## for the DOMINANT differing biome among them (most of the up-to-4
## neighbors sharing one biome wins; a tie keeps whichever was found
## first in a fixed scan order — a real but inconsequential tie-break,
## not a correctness question). direction is in the same local-space
## convention _build_sub_cell()'s own Vector2(col,row) positioning already
## uses (+X = right/higher col, +Y = down/higher row), matching the
## shader's own UV-space dot-product exactly with no extra transform.
func _compute_blend(row: int, col: int, biomes: Array, textures: Array) -> Dictionary:
	var self_i := row * _GRID_N + col
	var self_biome = biomes[self_i]
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var directions: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	var biome_counts: Dictionary = {}       # biome -> count among differing neighbors
	var biome_directions: Dictionary = {}   # biome -> Array[Vector2] of directions toward a neighbor with that biome
	var biome_texture: Dictionary = {}      # biome -> Texture2D (first non-null seen for that biome)
	for k in range(offsets.size()):
		var nc: int = col + offsets[k].x
		var nr: int = row + offsets[k].y
		if nc < 0 or nc >= _GRID_N or nr < 0 or nr >= _GRID_N:
			continue
		var ni := nr * _GRID_N + nc
		var n_biome = biomes[ni]
		if n_biome == null or n_biome == self_biome:
			continue
		var n_texture: Texture2D = textures[ni]
		if n_texture == null:
			continue  ## Can't blend toward a biome with no real texture (e.g. unauthored/flat-color-only) — skip rather than blend against a null.
		biome_counts[n_biome] = biome_counts.get(n_biome, 0) + 1
		if not biome_directions.has(n_biome):
			biome_directions[n_biome] = []
		biome_directions[n_biome].append(directions[k])
		if not biome_texture.has(n_biome):
			biome_texture[n_biome] = n_texture

	if biome_counts.is_empty():
		return {}

	var dominant_biome = null
	var dominant_count := -1
	for biome in biome_counts:
		if biome_counts[biome] > dominant_count:
			dominant_count = biome_counts[biome]
			dominant_biome = biome

	var avg_direction := Vector2.ZERO
	for dir in biome_directions[dominant_biome]:
		avg_direction += dir
	if avg_direction.length_squared() > 0.0001:
		avg_direction = avg_direction.normalized()

	return {
		"secondary_texture": biome_texture[dominant_biome],
		"direction": avg_direction,
		"weight": clampf(float(dominant_count) / 4.0, 0.0, 1.0) * _MAX_BLEND_WEIGHT,
	}

func _build_sub_cell(texture: Texture2D, biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility, local_pos: Vector2, cell_size: float, blend: Dictionary = {}) -> Node2D:
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ZERO, texture.get_size())
		sprite.position = local_pos
		var largest_dim := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (cell_size / largest_dim)
		if not blend.is_empty():
			var material := ShaderMaterial.new()
			material.shader = _get_blend_shader()
			material.set_shader_parameter("secondary_texture", blend["secondary_texture"])
			material.set_shader_parameter("blend_weight", blend["weight"])
			material.set_shader_parameter("blend_direction", blend["direction"])
			sprite.material = material
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
