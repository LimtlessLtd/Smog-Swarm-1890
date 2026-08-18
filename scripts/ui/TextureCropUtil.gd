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
## Image.get_used_rect() does the actual alpha-bounds scan in native code —
## cheap enough even at this pipeline's 2048x2048 render resolution to not
## need a background thread, but still cached per source texture (keyed by
## resource_path) since BuildMenuView rebuilds its whole icon grid on every
## tech_researched signal.

static var _cache: Dictionary = {}  # String (resource_path) -> Texture2D

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

	var used_rect := image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0 or used_rect.size == image.get_size():
		_cache[key] = texture  ## Fully-transparent (shouldn't happen for real art) or already tight — cropping would be a no-op.
		return texture

	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used_rect)
	_cache[key] = atlas
	return atlas
