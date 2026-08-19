class_name HUDScreenshotCapture
extends RefCounted

## Grabs a picture of the game world for a save slot's thumbnail — "we
## should also take a screenshot of the game window when saving (no menu
## dialogs should be visible in this screenshot)" (user request).
##
## MainHUD's fifth extracted collaborator (see that class's own header for
## the others): the only thing here that touches gameplay is the viewport
## it reads, and hiding/restoring the HUD around a capture is a concern of
## its own rather than another handler on MainHUD.
##
## Hides the WHOLE HUD CanvasLayer, not just the open dialog. The request
## was about menus, but a thumbnail of the map alone is both the cleanest
## reading of it and the more useful picture — a resource bar and build
## menu shrunk to 320 px wide are unreadable clutter, while the terrain and
## settlement underneath are exactly what makes one save recognisable from
## another.

## Thumbnail width in pixels; height follows from the viewport's aspect
## ratio. Wide enough to read a settlement's shape in a browser row, small
## enough that a campaign folder's worth of them is tens of KB rather than
## the megabytes full-resolution frames would cost.
const THUMBNAIL_WIDTH: int = 320

var _hud: CanvasLayer
var _viewport: Viewport

func _init(hud: CanvasLayer, viewport: Viewport) -> void:
	_hud = hud
	_viewport = viewport

## Returns the thumbnail, or null if there was nothing to capture (headless,
## or a viewport with no texture yet). MUST be awaited — a frame has to
## actually be drawn with the HUD hidden before the viewport holds a
## HUD-free image, and there is no way to force that synchronously.
func capture() -> Image:
	if _viewport == null:
		return null

	var was_visible := _hud != null and _hud.visible
	if was_visible:
		_hud.visible = false

	# get_image() returns whatever was drawn LAST, so setting visible=false
	# and reading immediately would hand back the previous frame — with the
	# HUD and the open Save dialog still in it. One frame_post_draw is the
	# wait for "a frame has now been drawn under the current visibility".
	# The HUD is missing for that single frame; at 60 fps that is not
	# perceptible, and it is the whole reason the shot comes out clean.
	await RenderingServer.frame_post_draw

	var texture := _viewport.get_texture()
	var image: Image = texture.get_image() if texture != null else null

	if was_visible:
		_hud.visible = true

	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return null

	var height := maxi(1, int(round(THUMBNAIL_WIDTH * float(image.get_height()) / float(image.get_width()))))
	image.resize(THUMBNAIL_WIDTH, height, Image.INTERPOLATE_LANCZOS)
	# RGB8, not the viewport's own RGBA8: the alpha channel is a constant 1
	# over a fully-painted game frame and only costs file size.
	image.convert(Image.FORMAT_RGB8)
	return image
