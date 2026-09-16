extends SceneTree

## Locks down how sprite art reaches the GPU: VRAM-compressed with a mip chain,
## sampled through that chain, and still that way after TextureCropUtil's crop
## copy. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_texture_import.gd
##
## Every sprite PNG was imported compress/mode=0 (lossless: RGBA8 in VRAM, 16.8 MB
## per 2048^2 source) with mipmaps/generate=false. Measured windowed with
## scripts/test/bench_texture_memory.gd, the four sprite categories held
## 1,446 MB of VRAM; after, 362 MB. Mipmaps stopped being harmless when D76 put
## figures at 17-46 px on screen: a ~900 px crop minified that far with no mip
## chain shimmers across a moving crowd.
##
## ## What each check is guarding against
##
## * **An asset added or re-imported at the editor's defaults.** Godot writes
##   compress/mode=0 and mipmaps/generate=false for a new PNG, so the next art
##   drop silently regresses. Check 1 reads every .import in the four
##   categories.
## * **Mipmaps generated and never sampled.** Godot's canvas default filter is
##   Linear, which reads level 0 only, so a mip chain would cost VRAM and change
##   nothing on screen. Check 2.
## * **The crop copy throwing the import away.** UnitVisuals, ZombieVisuals and
##   PropVisuals never draw the imported texture — they draw
##   TextureCropUtil.tight_crop_copy()'s ImageTexture, which uploads exactly the
##   Image it is built from. Before this change the copy decoded a compressed,
##   mipmapped import to bare RGBA8 with no chain, so check 1 passing alone
##   would have left 168 of the 214 sprite textures exactly as they were.
##   Check 3.
## * **The crop copy inventing an encoding.** The .import file is the one place
##   that decides; an uncompressed, unmipped source must come back that way.
##   Check 4.

const SPRITE_DIRS: Array[String] = ["res://assets/units", "res://assets/zombies", "res://assets/buildings", "res://assets/props"]

var _failures: Array[String] = []

func _init() -> void:
	_check_import_settings()
	_check_canvas_filter()
	_check_crop_keeps_encoding()
	_check_crop_invents_nothing()
	print()
	if _failures.is_empty():
		print("All texture import checks passed.")
		quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		quit(1)

func _check_import_settings() -> void:
	var checked := 0
	var wrong: Array[String] = []
	for dir_path in SPRITE_DIRS:
		for file_name in DirAccess.get_files_at(dir_path):
			if not file_name.ends_with(".png.import"):
				continue
			var config := ConfigFile.new()
			var path := dir_path.path_join(file_name)
			if config.load(path) != OK:
				wrong.append("%s (unreadable)" % path)
				continue
			checked += 1
			if int(config.get_value("params", "compress/mode", -1)) != 2 or not bool(config.get_value("params", "mipmaps/generate", false)):
				wrong.append(path)
	print("check 1: %d sprite .import files, %d not VRAM-compressed with mipmaps (want >0 files, 0 wrong)" % [checked, wrong.size()])
	if checked == 0:
		_failures.append("check 1: found no sprite .import files under %s" % [SPRITE_DIRS])
	for path in wrong:
		_failures.append("check 1: %s is not compress/mode=2 + mipmaps/generate=true" % path)

## The project setting's own enum is Nearest=0, Linear=1, Linear Mipmap=2,
## Nearest Mipmap=3 — not CanvasItem.TextureFilter, where 3 is
## NEAREST_WITH_MIPMAPS. The first cut of this change wrote 3 and got
## nearest-neighbour sprites; this check is what caught it.
const LINEAR_MIPMAP_SETTING: int = 2

func _check_canvas_filter() -> void:
	var filter := int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1))
	print("check 2: default canvas texture filter %d (want %d, Linear Mipmap)" % [filter, LINEAR_MIPMAP_SETTING])
	if filter != LINEAR_MIPMAP_SETTING:
		_failures.append("check 2: rendering/textures/canvas_textures/default_texture_filter is %d, not Linear Mipmap" % filter)

## A 64x64 frame with an opaque 20x36 figure inset, standing in for a rendered
## sprite on its transparent canvas.
func _figure_image() -> Image:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(24, 12, 20, 36), Color(0.6, 0.2, 0.1, 1.0))
	return image

func _check_crop_keeps_encoding() -> void:
	var source := _figure_image()
	source.generate_mipmaps()
	if source.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB) != OK:
		print("check 3: SKIP, this binary has no S3TC encoder to build the fixture with")
		return
	var cropped := TextureCropUtil.tight_crop_copy(ImageTexture.create_from_image(source))
	var image := cropped.get_image() if cropped else null
	if not image:
		_failures.append("check 3: tight_crop_copy() returned no readable image")
		return
	print("check 3: compressed+mipmapped 64x64 source -> %dx%d, compressed %s, mipmaps %s (want 20x36, true, true)" % [
		image.get_width(), image.get_height(), image.is_compressed(), image.has_mipmaps()])
	if image.get_size() != Vector2i(20, 36):
		_failures.append("check 3: crop is %s, want (20, 36)" % image.get_size())
	if not image.is_compressed():
		_failures.append("check 3: crop of a VRAM-compressed source came back uncompressed")
	if not image.has_mipmaps():
		_failures.append("check 3: crop of a mipmapped source came back with no mip chain")

func _check_crop_invents_nothing() -> void:
	var cropped := TextureCropUtil.tight_crop_copy(ImageTexture.create_from_image(_figure_image()))
	var image := cropped.get_image() if cropped else null
	if not image:
		_failures.append("check 4: tight_crop_copy() returned no readable image")
		return
	print("check 4: plain RGBA8 64x64 source -> %dx%d, compressed %s, mipmaps %s (want 20x36, false, false)" % [
		image.get_width(), image.get_height(), image.is_compressed(), image.has_mipmaps()])
	if image.get_size() != Vector2i(20, 36) or image.is_compressed() or image.has_mipmaps():
		_failures.append("check 4: crop of a plain source changed its encoding or size")
