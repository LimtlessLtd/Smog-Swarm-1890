class_name TerrainBoundaryBlend
extends RefCounted

## Finds the places in a baked chunk where one biome meets a different one,
## so TerrainMeshView can soften exactly those and nothing else.
##
## "I just want the edges blurred over a gradient at the very edge of each
## biome change though, don't apply it to the entire biome" (user request).
## The mesh already draws the real polygon shapes; what it draws is a hard
## cut at every boundary, which TerrainMeshView's own header has recorded as
## a known gap since the mesh went in.
##
## The softening is a CROSSFADE, not a blur. Along each boundary, a strip of
## fixed width is drawn inside the triangle on either side, textured with the
## OTHER side's biome, at half opacity on the shared edge and fading to
## nothing by the far side of the strip. Both sides do it, so the two
## textures mix 50/50 exactly on the boundary line and are pure again
## BAND_WIDTH away from it -- the biome interior is untouched, which is the
## part of the request that rules out a whole-surface blur or a softened
## texture.
##
## The strip's width is in WORLD UNITS, and that is the whole design. The
## first version faded across the whole triangle instead, which is simpler
## and looks correct in a diagram; rendered, it covered the map in a haze of
## triangular wedges radiating out of every boundary, because triangle size
## here is the real OSM boundary detail and runs median 24 / p95 94 / max 185
## world units. Fading across the max-size ones spread a neighbour's texture
## a third of a hex inland -- precisely the "don't apply it to the entire
## biome" failure the request warned about. A width the boundary cannot
## exceed is what makes it an edge treatment rather than a biome treatment.
##
## This owns where a crossing is and what shape it takes. Which surface it
## contributes to, and what it is textured with, is TerrainMeshView's
## business.

## Ints per crossing in the flat array find_crossings() returns:
##   0  triangle index being bled INTO
##   1  shared edge, first vertex index      -- full blend strength here
##   2  shared edge, second vertex index     -- and here
##   3  that triangle's remaining vertex     -- zero strength here
##   4  bake biome CODE on the other side (RealTerrainSampler.biome_from_code())
##
## One flat PackedInt32Array rather than an array of records: a chunk can
## produce thousands of crossings and a Dictionary or object per crossing
## would allocate thousands of times per chunk build, which already runs on a
## frame budget.
const CROSSING_STRIDE: int = 5

## Opacity of a neighbour's texture right on the shared edge. 0.5 is the
## value that makes the boundary read as soft rather than as MOVED: both
## sides bleed into each other by the same amount, so the exact 50/50 mix
## lands on the true boundary line. Anything higher and the neighbour's
## texture dominates its own side of a line it does not own.
const EDGE_ALPHA: float = 0.5

## How far the crossfade reaches inland from a boundary, in world units. Both
## sides bleed, so a boundary's whole transition is twice this -- about a
## fifth of TerrainMeshView's 93-unit texture repeat, against a 512-unit hex.
##
## Chosen by rendering the same framing at 0 (off), 10 and 18, at both ends of
## the Tactical zoom band. 0 is the hard cut this replaces and reads as
## shattered glass. 18 softens the boundary no more usefully than 10 when
## zoomed out, and visibly costs the interiors their definition when zoomed in
## -- brickwork on an urban patch stops reading as brickwork. 10 removes the
## cut at both zooms with the interiors untouched, which is the whole request.
const BAND_WIDTH: float = 10.0

## Ceiling on the strip as a FRACTION of the triangle's own height, applied
## on top of BAND_WIDTH. Without it a feature thinner than the band -- a
## river ribbon a few units across is the common case -- would be covered
## edge to edge by its neighbours bleeding in from both banks, and would
## render as a faint smudge instead of a river. Half leaves every feature a
## pure core however thin it is.
const MAX_BAND_FRACTION: float = 0.5


## Every biome-to-biome crossing in `data`, as CROSSING_STRIDE ints each.
##
## `kept` is one byte per triangle, 0 for triangles the caller dropped (ocean
## culling). Dropped triangles take no part: bleeding a biome into ground
## that is not drawn would put a fringe of land out over open sea, which is
## the artefact TerrainMeshView's own _is_on_land() culling exists to avoid.
##
## Edges shared by two triangles of the SAME biome are the common case and
## produce nothing, so an interior stays exactly as it renders today.
##
## Not detected, and visible: a biome change that falls on a CHUNK boundary.
## Each chunk is baked and loaded independently and the bake nodes the chunk
## border into its own arrangement, so no triangle spans two chunks and this
## can only ever see one side. Such a boundary keeps today's hard cut. It is
## a straight 4096-unit line among curved ones where it happens, but it is
## not a new artefact -- it is one place the improvement does not reach.
static func find_crossings(data: TerrainMeshChunkData, kept: PackedByteArray) -> PackedInt32Array:
	var crossings := PackedInt32Array()
	var indices := data.indices
	var codes := data.triangle_biomes
	# Edge -> the first triangle seen using it. The bake's arrangement is
	# noded, so adjacent faces share bit-identical vertices and therefore
	# share INDICES -- an exact integer match, with no tolerance to pick and
	# no chance of two coincident-but-distinct vertices missing each other.
	# (The bake measures 0 T-junctions for exactly this reason.)
	var edge_owner: Dictionary = {}

	for tri in data.triangle_count():
		if kept[tri] == 0:
			continue
		var base := tri * 3
		for e in 3:
			var a := indices[base + e]
			var b := indices[base + (e + 1) % 3]
			# Order-independent key. Both indices are uint16 in the wire
			# format, so the shift cannot collide inside GDScript's 64-bit int.
			var key := (mini(a, b) << 16) | maxi(a, b)
			var owner: Variant = edge_owner.get(key)
			if owner == null:
				edge_owner[key] = tri
				continue
			var other: int = owner
			if codes[other] == codes[tri]:
				continue
			# Both directions, so each side softens into the other and the
			# mix lands symmetrically on the boundary.
			crossings.append_array(_crossing(indices, tri, a, b, codes[other]))
			crossings.append_array(_crossing(indices, other, a, b, codes[tri]))

	return crossings


## The crossfade strip for one crossing, as two triangles: 6 points, with
## `out_alphas` filled to match. Empty for a degenerate triangle (zero-length
## edge, or an opposite vertex on the edge's own line) -- there is no
## interior to fade across and the strip would have no area.
##
## The strip is the shared edge offset PERPENDICULARLY into the triangle. The
## obvious alternative -- walking each endpoint toward the opposite vertex --
## also gives constant perpendicular width, and was tried: on a skinny
## triangle that walk is mostly sideways rather than inward, so the strip
## shears along the boundary and small patches rendered with a soft gradient
## running off in one direction instead of an even fringe. `opposite` is used
## only to decide which of the two normals points inward.
##
## The inner edge is also pulled IN along the boundary by the same distance,
## making a trapezoid rather than a rectangle. A rectangle's inner corners
## poke out through the triangle's other two sides wherever those slant back
## (any obtuse triangle, of which there are many), and each poked-out corner
## rendered as a thin bright spike sticking out of the boundary -- clearly
## visible as radial flares along every river bank. The 45-degree inset keeps
## the strip inside the triangle for any corner at or above a right angle,
## and shrinks harmlessly toward a sliver for sharper ones.
static func band(edge_a: Vector2, edge_b: Vector2, opposite: Vector2, out_alphas: Array) -> PackedVector2Array:
	var along := edge_b - edge_a
	var length := along.length()
	if length <= 0.0:
		return PackedVector2Array()
	var normal := Vector2(-along.y, along.x) / length
	var signed_height := (opposite - edge_a).dot(normal)
	if is_zero_approx(signed_height):
		return PackedVector2Array()
	var inward := normal if signed_height > 0.0 else -normal

	var reach := minf(BAND_WIDTH, absf(signed_height) * MAX_BAND_FRACTION)
	# Clamped so the two inset corners cannot cross past each other on an edge
	# shorter than twice the reach — they meet in the middle instead, which
	# collapses the trapezoid to a triangle rather than folding it inside out.
	var inset := (along / length) * minf(reach, length * 0.5)
	var inner_a := edge_a + inward * reach + inset
	var inner_b := edge_b + inward * reach - inset

	out_alphas.append_array([EDGE_ALPHA, EDGE_ALPHA, 0.0, EDGE_ALPHA, 0.0, 0.0])
	return PackedVector2Array([
		edge_a, edge_b, inner_b,
		edge_a, inner_b, inner_a,
	])


static func _crossing(indices: PackedInt32Array, tri: int, a: int, b: int, neighbour_code: int) -> PackedInt32Array:
	return PackedInt32Array([tri, a, b, _opposite(indices, tri, a, b), neighbour_code])


## The one vertex of `tri` that is not on edge (a, b). Returns `a` if the
## triangle is degenerate (two identical indices) -- that collapses the
## crossing to zero area and draws nothing, which is the right outcome for
## geometry that has no interior to fade across.
static func _opposite(indices: PackedInt32Array, tri: int, a: int, b: int) -> int:
	var base := tri * 3
	for i in 3:
		var v := indices[base + i]
		if v != a and v != b:
			return v
	return a
