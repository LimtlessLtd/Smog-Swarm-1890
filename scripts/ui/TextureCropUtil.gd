class_name TextureCropUtil
extends RefCounted

## Crops a texture to the tight bounding box of its own non-transparent
## pixels, wrapped in an AtlasTexture (a view into the original — no pixel
## data copied/re-encoded). Fixes icons that read as small inside their UI
## box despite already being STRETCH_KEEP_ASPECT_CENTERED-fit to it:
## "aspect-fit the whole texture" and "aspect-fit the visible model" are
## different crops, and only the second one fills a small UI box edge-to-
## edge. "make the building images on the building browser menu auto size
## to take up all the available space within the box" (user request) —
## BuildingIconButton is the first, but not necessarily only, consumer.
##
## Now largely a no-op for buildings/icons: this was written when
## tools/blender_pipeline/render_common.py's add_camera() framed every
## asset at a fixed ortho_scale=3.0 aimed at the world origin, which left
## a building filling 23.6-48.6% of its own PNG and an icon 15.1-45.9%.
## frame_content() sizes the frame to the model instead, so those source
## PNGs now carry ~95% ink and get_used_rect() finds little to trim. Kept
## because it costs one cached alpha scan, it still earns its keep on any
## category not yet re-rendered fitted (units, zombies, props), and it is
## the only thing standing between a small UI box and a hand-authored .svg
## with its own arbitrary margins.
##
## Two crops, because the AtlasTexture view does not survive every renderer
## — see tight_crop_copy(). UnitVisuals/ZombieVisuals take the copy;
## BuildingIconButton takes the view.
##
## Image.get_used_rect() does the actual alpha-bounds scan in native code —
## cheap enough even at this pipeline's 2048x2048 render resolution to not
## need a background thread, but still cached per source texture (keyed by
## resource_path) since BuildMenuView rebuilds its whole icon grid on every
## tech_researched signal.

static var _cache: Dictionary = {}       # String (resource_path) -> Texture2D (AtlasTexture view)
static var _copy_cache: Dictionary = {}  # String (resource_path) -> Texture2D (ImageTexture copy)

static func tight_crop(texture: Texture2D) -> Texture2D:
	if not texture:
		return null
	var key := texture.resource_path
	if key.is_empty():
		return texture  ## No stable cache key (an in-memory-only texture) — return uncropped rather than risk caching under a colliding empty key.
	if _cache.has(key):
		return _cache[key]

	var image := texture.get_image()
	if not image:
		_cache[key] = texture
		return texture
	if image.is_compressed():
		image.decompress()  ## get_used_rect() reads no block-compressed format; get_image() returns a copy, so the source texture keeps its VRAM encoding.

	var used_rect := image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0 or used_rect.size == image.get_size():
		_cache[key] = texture  ## Fully-transparent (shouldn't happen for real art) or already tight — cropping would be a no-op.
		return texture

	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used_rect)
	_cache[key] = atlas
	return atlas

## The same crop as tight_crop(), as a standalone ImageTexture holding only the
## cropped pixels rather than a view into the original.
##
## Required wherever the result can reach a MultiMesh, and that is a measured
## constraint rather than a precaution: MultiMeshInstance2D draws through
## RenderingServer.canvas_item_add_multimesh(), which takes a texture RID, and
## AtlasTexture.get_rid() returns its ATLAS's RID. A probe confirmed
## `atlas.get_rid() == source.get_rid()` and the whole uncropped frame stretched
## across the quad with the region dropped. Sprite2D is unaffected (it goes
## through Texture2D.draw_rect_region), but TacticalEntityLayer draws the same
## zombie texture through both paths, so the crop has to be real pixels.
##
## Costs one image copy and gets VRAM back for it: nothing here retains the
## source, so a zombie frame carrying 22.3% x 40.3% ink leaves ~1.5 MB resident
## instead of the 2048^2 RGBA8 source's 16.8 MB.
##
## The copy carries the source's own import encoding forward, so the .import
## file stays the one place that decides it. ImageTexture.create_from_image()
## uploads exactly the Image it is given: without this step the crop decodes a
## VRAM-compressed, mipmapped import back to bare RGBA8 with no mip chain, and
## a figure minified from ~900 px to 17-46 px shimmers across a moving crowd.
## If the source had mipmaps the crop regenerates them; if it was
## block-compressed the crop is re-encoded to the same family. Image.compress()
## needs an encoder compiled into the running binary (the editor build this
## project runs from has one) — where it returns an error the crop stays RGBA8
## with its mipmaps rather than failing to draw.
static func tight_crop_copy(texture: Texture2D) -> Texture2D:
	if not texture:
		return null
	var key := texture.resource_path
	if not key.is_empty() and _copy_cache.has(key):
		return _copy_cache[key]

	var cropped := texture
	var image := texture.get_image()
	if image:
		var source_format := image.get_format()
		var source_mipmaps := image.has_mipmaps()
		if source_mipmaps:
			image.clear_mipmaps()  ## Only level 0 is sliced, and dropping the chain first spares decompress() decoding it.
		if image.is_compressed():
			image.decompress()  ## get_region() cannot slice a block-compressed image.
		var used_rect := image.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0 and used_rect.size != image.get_size():
			var region := image.get_region(used_rect)
			if source_mipmaps:
				region.generate_mipmaps()
			var compress_mode := _compress_mode_for(source_format)
			if compress_mode >= 0:
				region.compress(compress_mode, Image.COMPRESS_SOURCE_SRGB)
			cropped = ImageTexture.create_from_image(region)
	if not key.is_empty():
		_copy_cache[key] = cropped  ## Fully-transparent or already-tight art caches the source itself — copying it would buy nothing.
	return cropped

## The Image.CompressMode that re-encodes to the same block-compression family
## as `format`, or -1 for an uncompressed format.
static func _compress_mode_for(format: Image.Format) -> int:
	match format:
		Image.FORMAT_DXT1, Image.FORMAT_DXT3, Image.FORMAT_DXT5:
			return Image.COMPRESS_S3TC
		Image.FORMAT_BPTC_RGBA:
			return Image.COMPRESS_BPTC
		Image.FORMAT_ETC2_R11, Image.FORMAT_ETC2_RGB8, Image.FORMAT_ETC2_RGBA8, Image.FORMAT_ETC2_RGB8A1:
			return Image.COMPRESS_ETC2
		Image.FORMAT_ASTC_4x4:
			return Image.COMPRESS_ASTC
		_:
			return -1
