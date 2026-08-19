class_name ReliefImageBuilder
extends RefCounted

## Synthesises the relief/impassability overlay image from the baked terrain
## rasters. Pure computation: no scene tree, no drawing, no visibility —
## ElevationReliefView owns all of that and only asks this for a texture.
##
## Works per RASTER PIXEL, never per hex. RealTerrainSampler's rasters are
## RealTerrainSampler.WORLD_UNITS_PER_PIXEL (90 wu, about 878 real metres)
## per pixel and a macro hex is 2 * HexCoord.HEX_SIZE wu across, so this
## resolves roughly 11x11 samples inside every hex where the old per-hex
## overlay had exactly one. That is the granularity rule in CLAUDE.md §3
## applied to a visual: a hex that is mostly dry with one marsh strip now
## shows the strip, not a hex-shaped verdict about the strip.
##
## 878 m/pixel is the real ceiling on this, not a chosen shortcut — the
## fine per-hex tiles (RealTerrainSampler's "Fine per-hex tiles" section)
## bake biome and terrain_feature at 30 m but deliberately do NOT bake
## elevation, so there is no finer elevation data in the project to draw.
## Crisper relief at Tactical zoom needs a fine elevation bake in
## tools/geo_bake, not a change here; bilinear filtering on the resulting
## texture (ElevationReliefView sets it) is what keeps the interpolation
## between real samples smooth rather than blocky in the meantime.
##
## Two cues are composited into the one RGBA image, so one texture and one
## draw call carry both:
##
##   - HILLSHADE. Standard directional relief: the elevation gradient at each
##     pixel gives a surface normal, lit from a fixed north-west sun. A slope
##     facing the light brightens, one facing away darkens. This is the cue
##     that makes ground "actually look as though [it is] higher/lower in
##     elevation than their neighbours" (user report) — a flat per-band tint
##     cannot, because it colours a plateau and a cliff face identically.
##     Shading is by SLOPE, so it works at every zoom and needs no legend.
##   - IMPASSABLE MARKING. Ground a player cannot walk on, tinted per pixel.
##
## Alpha is kept low throughout: this composites over real terrain art that
## already carries biome colour, so it must shade that art rather than
## replace it.

## Fixed light direction, in raster-pixel space (+x right, +y down, so a
## negative y component points north). North-west is the cartographic
## convention: relief lit from any southerly direction reads INVERTED to most
## people (hills look like pits), which is a documented perceptual effect and
## not worth being clever about.
const _LIGHT_DIR := Vector2(-0.707, -0.707)

## Vertical exaggeration applied before the normal is computed. Real British
## terrain over an 878 m pixel is a very gentle gradient — a metre of rise per
## metre of run essentially never happens at this sample spacing — so an
## honest 1:1 normal produces a nearly flat, invisible shade. This scales the
## gradient so the relief reads. A presentation number, not a claim about the
## terrain: it changes how visible a slope is, never which band it is in or
## whether it is passable.
const _VERTICAL_EXAGGERATION: float = 14.0

## How far the hillshade can push a pixel away from neutral, as alpha. The
## shade is drawn as black at varying alpha for slopes facing away and white
## at varying alpha for slopes facing the light.
const _SHADE_MAX_ALPHA: float = 0.42
const _LIGHT_MAX_ALPHA: float = 0.30

## Impassable ground. Kept as a flat wash rather than the hatching the
## per-hex overlay used: hatching has to be generated per closed shape, and
## at raster resolution impassable ground is an arbitrary blob spanning many
## pixels and several hexes, with no hex outline left to clip lines to.
## A saturated red at low alpha reads as "blocked" over every biome texture.
const _IMPASSABLE_COLOR := Color(0.62, 0.10, 0.07, 0.34)

## Metres of elevation change across one pixel that counts as a full-strength
## slope. Above this the shade saturates instead of clipping to pure black or
## white — real escarpment edges in this data exceed any sane linear mapping.
const _SLOPE_METRES_AT_FULL_SHADE: float = 55.0


## Builds the overlay for the whole baked raster, or null when the bake is
## missing (same "not available" contract RealTerrainSampler.is_available()
## exposes) — the caller draws nothing rather than a blank rectangle.
##
## `hex_grid_map` supplies ONLY the mountain verdict, per hex, and only
## because that verdict is not in the raster: MountainPassCarver lowers a
## ridge hex's HexCell.elevation at generation to open a pass, and that carve
## exists nowhere in the baked elevation data. Rendering mountains straight
## from raster elevation would therefore paint a solid impassable ridge
## across passes the player can genuinely walk through. Marsh, peat bog and
## ocean have no such generated exception and are read per pixel.
static func build(hex_grid_map: HexGridMap) -> Image:
	var elevation_image := RealTerrainSampler.get_elevation_image()
	var landcover_image := RealTerrainSampler.get_landcover_image()
	if elevation_image == null or landcover_image == null:
		return null

	var width := elevation_image.get_width()
	var height := elevation_image.get_height()
	if width < 3 or height < 3 or landcover_image.get_width() != width or landcover_image.get_height() != height:
		return null
	# Both decoders below index raw bytes at a computed stride and read three
	# channels per pixel. A single-channel or 16-bit format would make every
	# read land mid-pixel and produce plausible-looking garbage rather than an
	# error, so the format is checked rather than assumed — the bake writes
	# 8-bit RGB and RealTerrainSampler loads it with Image.load() specifically
	# to bypass the import pipeline, but nothing here can enforce that.
	if not _is_byte_rgb(elevation_image) or not _is_byte_rgb(landcover_image):
		push_error("ReliefImageBuilder: terrain rasters are not 8-bit RGB/RGBA, refusing to decode them")
		return null

	# Both rasters are decoded ONCE into flat arrays and then indexed
	# arithmetically. get_pixelv() per neighbour would be four Godot calls
	# and four Color allocations per pixel across ~550k pixels; the hillshade
	# needs every pixel's four neighbours, so that is the difference between
	# a visible startup stall and not one.
	var metres := _smoothed(_decode_elevation_metres(elevation_image, width, height), width, height)
	var impassable := _decode_impassable(landcover_image, width, height, hex_grid_map)

	var out := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			out.set_pixel(x, y, _pixel_color(metres, impassable, x, y, width, height))
	return out


static func _is_byte_rgb(image: Image) -> bool:
	var format := image.get_format()
	return format == Image.FORMAT_RGB8 or format == Image.FORMAT_RGBA8


## Elevation in real metres per pixel, in the same RGB packing
## RealTerrainSampler.sample_at() decodes (AWS/Mapzen Terrain-RGB:
## r * 256 + g + b / 256 - 32768).
static func _decode_elevation_metres(image: Image, width: int, height: int) -> PackedFloat32Array:
	var raw := image.get_data()
	var stride := raw.size() / (width * height)  ## 3 for RGB8, 4 for RGBA8 — the bake writes RGB but an import could widen it.
	var out := PackedFloat32Array()
	out.resize(width * height)
	for i in range(width * height):
		var base := i * stride
		out[i] = float(raw[base] * 256 + raw[base + 1]) + float(raw[base + 2]) / 256.0 - 32768.0
	return out


## 3x3 box blur over the elevation, run once before any gradient is taken.
##
## Not a stylistic softening — it removes a real artefact. The source terrain
## tiles quantise elevation, so flat ground carries small step edges between
## equal-value plateaus, and a gradient operator turns every one of those steps
## into a lit ridge. Unsmoothed, the shade showed the quantisation as a grid of
## rectangular terraces across otherwise flat farmland, which reads as terrain
## that is not there. One pixel of blur is well under the ~878 m sample spacing
## the real landforms occupy, so hills, scarps and valleys survive it — only
## the single-sample steps between equal values do not.
##
## Separable (horizontal then vertical) rather than a 9-tap kernel per pixel:
## same result, two passes of three taps instead of one of nine.
static func _smoothed(metres: PackedFloat32Array, width: int, height: int) -> PackedFloat32Array:
	var horizontal := PackedFloat32Array()
	horizontal.resize(metres.size())
	for y in range(height):
		var row := y * width
		for x in range(width):
			horizontal[row + x] = (
				metres[row + maxi(x - 1, 0)]
				+ metres[row + x]
				+ metres[row + mini(x + 1, width - 1)]
			) / 3.0

	var out := PackedFloat32Array()
	out.resize(metres.size())
	for y in range(height):
		var up := maxi(y - 1, 0) * width
		var mid := y * width
		var down := mini(y + 1, height - 1) * width
		for x in range(width):
			out[mid + x] = (horizontal[up + x] + horizontal[mid + x] + horizontal[down + x]) / 3.0
	return out


## Per-pixel "a player cannot walk here", as 1/0 bytes.
##
## Marsh, peat bog and ocean come from the landcover raster's own per-pixel
## codes — the same three clauses HexCell.is_passable() applies, evaluated at
## raster resolution instead of once per hex. The mountain clause instead
## reads the macro hex, for the pass-carving reason build() documents.
static func _decode_impassable(image: Image, width: int, height: int, hex_grid_map: HexGridMap) -> PackedByteArray:
	var raw := image.get_data()
	var stride := raw.size() / (width * height)
	var origin := RealTerrainSampler.get_raster_origin_world()
	var out := PackedByteArray()
	out.resize(width * height)

	var mountain_by_hex: Dictionary = {}  ## Vector2i -> bool, memoised: ~11x11 pixels share one hex, so this asks HexGridMap once per hex rather than once per pixel.
	for y in range(height):
		for x in range(width):
			var i := y * width + x
			var base := i * stride
			var biome := RealTerrainSampler.biome_from_code(int(raw[base]))
			var feature := RealTerrainSampler.feature_from_code(int(raw[base + 1]))
			if feature == GameEnums.TerrainFeature.MARSH or feature == GameEnums.TerrainFeature.PEAT_BOG or biome == GameEnums.BiomeType.OCEAN:
				out[i] = 1
				continue
			var world := origin + Vector2(float(x), float(y)) * RealTerrainSampler.WORLD_UNITS_PER_PIXEL
			var hex := HexCoord.world_to_axial(world)
			if not mountain_by_hex.has(hex):
				var cell := hex_grid_map.get_cell(hex) if hex_grid_map else null
				mountain_by_hex[hex] = cell != null and ElevationLevels.is_impassable(cell.height_level())
			out[i] = 1 if mountain_by_hex[hex] else 0
	return out


## Hillshade composited with the impassable wash for one pixel.
##
## The gradient uses each neighbour pair straddling the pixel (a central
## difference), clamped at the raster edge so an edge pixel differences
## against itself and reads as flat rather than as a cliff.
static func _pixel_color(metres: PackedFloat32Array, impassable: PackedByteArray, x: int, y: int, width: int, height: int) -> Color:
	var left := metres[y * width + maxi(x - 1, 0)]
	var right := metres[y * width + mini(x + 1, width - 1)]
	var up := metres[maxi(y - 1, 0) * width + x]
	var down := metres[mini(y + 1, height - 1) * width + x]

	# Downhill-facing brightness: the dot of the (negated) gradient with the
	# light direction. Positive means the surface tilts toward the light.
	var gradient := Vector2(right - left, down - up) * 0.5
	var lit := -(gradient.x * _LIGHT_DIR.x + gradient.y * _LIGHT_DIR.y) * _VERTICAL_EXAGGERATION
	var strength := clampf(lit / (_SLOPE_METRES_AT_FULL_SHADE * _VERTICAL_EXAGGERATION), -1.0, 1.0)

	var shade: Color
	if strength >= 0.0:
		shade = Color(1.0, 0.99, 0.94, strength * _LIGHT_MAX_ALPHA)
	else:
		shade = Color(0.05, 0.06, 0.10, -strength * _SHADE_MAX_ALPHA)

	if impassable[y * width + x] == 0:
		return shade
	# Impassable wash OVER the shade, alpha-composited here rather than as a
	# second texture: one image means one draw call and no z-ordering question
	# between the two cues.
	var a := _IMPASSABLE_COLOR.a + shade.a * (1.0 - _IMPASSABLE_COLOR.a)
	if a <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var blended := (_IMPASSABLE_COLOR * _IMPASSABLE_COLOR.a + shade * shade.a * (1.0 - _IMPASSABLE_COLOR.a)) / a
	return Color(blended.r, blended.g, blended.b, a)


## World-space rect the built image covers — the caller draws the texture
## into exactly this, so the overlay lands on the terrain it was sampled
## from. Derived from the raster's own origin and pixel size rather than any
## hex extent, so it cannot drift from _pixel_for_world()'s mapping.
static func world_rect(image: Image) -> Rect2:
	var origin := RealTerrainSampler.get_raster_origin_world()
	var size := Vector2(float(image.get_width()), float(image.get_height())) * RealTerrainSampler.WORLD_UNITS_PER_PIXEL
	return Rect2(origin, size)
