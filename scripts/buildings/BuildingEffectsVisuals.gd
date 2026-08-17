class_name BuildingEffectsVisuals
extends RefCounted

## Derives which lightweight "alive" visual (smoke / fire / pulsing light) a
## finished, non-ruined building gets in Tactical view, and builds the
## actual effect nodes — TacticalHexView attaches whichever apply to a given
## BuildingInstance's own container. "simple, smoke particle effects, fire
## particle effects and light animations... so they look that little bit
## more alive and immersive" (user request).
##
## Derived from EXISTING BuildingDefinition data, not a hardcoded per-
## BuildingType list — stays correct for any future building with no second
## table to keep in sync:
##   - Smoke: INDUSTRY_EXTRACTION buildings that burn COAL (daily_upkeep) or
##     turn a raw resource into a processed one (daily_output has any of
##     BRICKS/IRON/STEEL/CONCRETE/GUNPOWDER) — a proxy for "has a smokestack".
##   - Fire: the smelting/forging subset of the above — burns COAL AND
##     outputs IRON/STEEL/GUNPOWDER specifically (Bessemer Smelting Complex,
##     Iron Foundry, Steelworks, Steam Furnace, Gunpowder Mill/Synthetic
##     Refinery) — visibly hotter than a coal mine/pithead that only
##     extracts, never smelts. Fire buildings ALSO get smoke (a real
##     furnace produces both), so TacticalHexView checks has_fire() first.
##   - Light: BuildingDefinition.lit_at_night directly — the SAME field
##     FogOfWarManager already reads for night vision; a building already
##     tagged as a light source in the sim gets one in the visuals too.
##
## Particles are plain CPUParticles2D (not GPUParticles2D — this project has
## no other GPU-particle usage to justify the extra setup, and CPU particles
## at ~10 buildings' worth of onscreen instances is nowhere near a real
## budget concern) using a small procedurally-generated soft-dot texture
## (_soft_dot_texture(), cached once) rather than a Blender-rendered asset —
## a flat-colored square is what CPUParticles2D draws with no texture at
## all, which reads as blocky/wrong for smoke or fire; a runtime radial
## gradient is a few lines of code and needs no pipeline/asset dependency.

const _FIRE_OUTPUT_TYPES: Array[GameEnums.ResourceType] = [GameEnums.ResourceType.IRON, GameEnums.ResourceType.STEEL, GameEnums.ResourceType.GUNPOWDER]
const _SMOKE_OUTPUT_TYPES: Array[GameEnums.ResourceType] = [GameEnums.ResourceType.BRICKS, GameEnums.ResourceType.IRON, GameEnums.ResourceType.STEEL, GameEnums.ResourceType.CONCRETE, GameEnums.ResourceType.GUNPOWDER]

static func has_smoke(definition: BuildingDefinition) -> bool:
	if definition.category != GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
		return false
	if definition.daily_upkeep.has(GameEnums.ResourceType.COAL):
		return true
	for resource_type in _SMOKE_OUTPUT_TYPES:
		if definition.daily_output.has(resource_type):
			return true
	return false

static func has_fire(definition: BuildingDefinition) -> bool:
	if not definition.daily_upkeep.has(GameEnums.ResourceType.COAL):
		return false
	for resource_type in _FIRE_OUTPUT_TYPES:
		if definition.daily_output.has(resource_type):
			return true
	return false

static func has_light(definition: BuildingDefinition) -> bool:
	return definition.lit_at_night

static var _soft_dot_texture_cache: ImageTexture
const _DOT_SIZE: int = 16

## A small white circle, alpha falling off toward the edge (squared for a
## softer edge than a linear ramp) — WHITE so each particle system's own
## `color`/`color_ramp` tints it, one shared texture for smoke/fire/light
## alike rather than three separately-colored ones.
static func _soft_dot_texture() -> ImageTexture:
	if _soft_dot_texture_cache:
		return _soft_dot_texture_cache
	var image := Image.create(_DOT_SIZE, _DOT_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(_DOT_SIZE, _DOT_SIZE) * 0.5
	var max_dist := _DOT_SIZE * 0.5
	for y in range(_DOT_SIZE):
		for x in range(_DOT_SIZE):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf(1.0 - dist / max_dist, 0.0, 1.0)
			alpha *= alpha
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_soft_dot_texture_cache = ImageTexture.create_from_image(image)
	return _soft_dot_texture_cache

static var _add_blend_material: CanvasItemMaterial
static func _additive_material() -> CanvasItemMaterial:
	if not _add_blend_material:
		_add_blend_material = CanvasItemMaterial.new()
		_add_blend_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_blend_material

static var _light_pulse_shader: Shader
static func _get_light_pulse_shader() -> Shader:
	if not _light_pulse_shader:
		_light_pulse_shader = load("res://assets/shaders/light_pulse.gdshader") as Shader
	return _light_pulse_shader

static func build_smoke_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "SmokeEffect"
	p.texture = _soft_dot_texture()
	p.amount = 10
	p.lifetime = 2.5
	p.emitting = true
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.gravity = Vector2(0, -14.0)  ## Upward drift — CPUParticles2D's own "gravity" is just a constant acceleration, sign and all.
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.64, 0.55))
	ramp.set_color(1, Color(0.62, 0.62, 0.64, 0.0))
	p.color_ramp = ramp
	return p

static func build_fire_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "FireEffect"
	p.texture = _soft_dot_texture()
	p.amount = 8
	p.lifetime = 0.9
	p.emitting = true
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2(0, -30.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.15, 0.9))
	ramp.set_color(1, Color(0.6, 0.08, 0.0, 0.0))
	p.color_ramp = ramp
	p.material = _additive_material()  ## Glows against the ground instead of drawing as a flat translucent dot.
	return p

static func build_light_glow() -> Sprite2D:
	var glow := Sprite2D.new()
	glow.name = "LightGlow"
	glow.texture = _soft_dot_texture()
	glow.modulate = Color(1.0, 0.92, 0.65, 0.6)
	glow.scale = Vector2.ONE * 3.5
	var material := ShaderMaterial.new()
	material.shader = _get_light_pulse_shader()
	glow.material = material
	return glow
