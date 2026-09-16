extends Node

## Measures what the sprite art costs once it is on the GPU: VRAM held, the
## wall-clock cost of first use, and what each cached texture actually is
## (size, format, mipmaps), per asset category, through the same
## UnitVisuals/ZombieVisuals/PropVisuals/BuildingVisuals entry points the game
## draws with.
##
## Run (NOT --headless -- the dummy rendering server allocates no texture
## storage, so RENDER_TEXTURE_MEM_USED reads 0 for everything):
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/bench_texture_memory.tscn
##
## Each category is loaded once in a fresh process, so its time is a cold
## first use (PNG import cache already on disk, no ResourceLoader cache). VRAM
## is the RENDER_TEXTURE_MEM_USED delta across the category after two frames,
## by which point the uncropped sources the crop copy released are freed.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("[bench_texture_memory] category | textures | vram MB | load ms | example size | format | mipmaps")
	await _measure("units", _unit_textures)
	await _measure("zombies", _zombie_textures)
	await _measure("props", _prop_textures)
	await _measure("buildings", _building_textures)
	get_tree().quit(0)

func _measure(label: String, loader: Callable) -> void:
	var before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var start := Time.get_ticks_usec()
	var textures: Array[Texture2D] = loader.call()
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
	await get_tree().process_frame
	await get_tree().process_frame
	var after := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var example := "-"
	var format := "-"
	var mipmaps := "-"
	if not textures.is_empty():
		var image := textures[0].get_image()
		example = "%dx%d" % [textures[0].get_width(), textures[0].get_height()]
		if image:
			format = str(image.get_format())
			mipmaps = str(image.has_mipmaps())
	print("[bench_texture_memory] %s | %d | %.1f | %.0f | %s | %s | %s" % [
		label, textures.size(), (after - before) / 1048576.0, elapsed_ms, example, format, mipmaps])

func _unit_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for unit_type in GameEnums.UnitType.values():
		for facing in GameEnums.Facing8.values():
			var texture := UnitVisuals.unit_texture(unit_type, facing)
			if texture and not out.has(texture):
				out.append(texture)
	return out

func _zombie_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for variant in ZombieVisuals.VARIANT_COUNT:
		for facing in GameEnums.Facing8.values():
			var texture := ZombieVisuals.zombie_texture(variant, facing)
			if texture and not out.has(texture):
				out.append(texture)
	return out

func _prop_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for prop_type in GameEnums.PropType.values():
		var texture := PropVisuals.prop_texture(prop_type)
		if texture and not out.has(texture):
			out.append(texture)
	return out

func _building_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for building_type in GameEnums.BuildingType.values():
		var texture := BuildingVisuals.building_texture(building_type)
		if texture and not out.has(texture):
			out.append(texture)
	return out
