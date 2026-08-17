"""Shared Blender render rig for SMOG-SWARM-1890's art pipeline.

Every asset (resource icon, unit, building, prop, wall, zombie, terrain
tile) is a real Blender scene built from primitives, rendered headless to
a transparent PNG. This module owns everything an asset script should NOT
have to repeat: scene reset, camera angle/framing per asset category,
flat unshaded materials, the black outline, and render/output settings.

Run via: blender --background --python render.py -- <args>
(everything after the bare "--" is this pipeline's own argv, not Blender's)

Not part of the Godot project itself — no GDScript, no scene tree. Lives
outside scripts/ on purpose so it's never mistaken for game code.
"""

import bpy
import math
import mathutils

# Category -> camera elevation angle in degrees above the horizon.
# Matches the "Style DNA" view conventions already written down in
# assets/units/README.md, assets/buildings/README.md and
# assets/icons/README.md before this pipeline replaced their AI-prompt
# workflow: units/buildings/props/walls/zombies/terrain use a steep
# bird's-eye camera to match the game's own top-down view; icons use a
# shallower 3/4 angle because a literal top-down lump reads as a blob at
# icon size (icons/README.md's own documented reasoning, carried over
# verbatim since it's a rendering-legibility fact, not an AI-prompt
# artifact).
CATEGORY_ELEVATION_DEG = {
    "icons": 55.0,
    # 75 (buildings/props/walls' angle) foreshortened a standing figure down
    # to almost nothing but its own head/helmet — measured directly on a
    # real rendered unit (truncheoneer.py), not assumed. 58 is close to
    # icons' own 55 for the same reason: anything with a body needs enough
    # side-on angle for the torso/legs to actually read as a silhouette.
    "units": 58.0,
    # Lowered from 75 for the same reason units moved off it — a steep
    # bird's-eye angle showed mostly rooftop and hid facade detail
    # (doors/walls/chimneys) the reference hand-illustrated buildings
    # (assets/buildings/cast_iron_foundry.png) show clearly. Not as low as
    # icons' 55 since these are still full 3D scenes meant to sit
    # believably on the hex grid, not flat UI glyphs.
    "buildings": 60.0,
    "props": 75.0,
    # Much shallower than every other category — a wall is meant to be read
    # as a barrier FACE (like a fence texture), not a rooftop; a steep
    # bird's-eye angle would show almost nothing but its thin top edge.
    "walls": 35.0,
    "zombies": 58.0,  # Same reasoning as units — a standing/shambling figure, not a flat object.
    "terrain": 90.0,  # straight down — terrain tiles are flat-viewed, no side ever visible
}

# Freestyle thickness is in absolute render-resolution pixels, not a fraction of frame
# size — a 3px line was nearly invisible once downscaled to the 20x20 HUD icon size
# icons/README.md documents. Scale as a fraction of resolution instead so the outline
# stays "thick bold" (that README's own words) at whatever size the asset is actually
# displayed at in-game, not just at native render resolution.
OUTLINE_THICKNESS_FRACTION = 0.018

# Shared between add_flat_light() (cosmetic — the Sun object itself lights nothing,
# see flat_material()) and flat_material()'s toon shader, which needs the same
# direction baked in as a shader-graph constant so the fake NdotL terminator lines up
# with where a real light would actually be if anyone ever re-lit this scene for real.
LIGHT_EULER = (math.radians(55), 0.0, math.radians(35))

# Where the 2-tone terminator falls, in remapped-dot-product space (0.5 == exactly the
# geometric terminator; nudged up so more of the model reads as "lit" — an all-shadow
# silhouette from some angles read worse at icon size than a slightly-too-bright one).
TOON_TERMINATOR = 0.42
TOON_SHADOW_MULT = 0.55  # shadow tone = base color * this, not a flat gray — keeps hue


def reset_scene():
    """Start from a genuinely empty scene — no default cube/light/camera to forget to delete."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_render(resolution: int):
    """Cycles + Freestyle + transparent film. Cycles chosen over Eevee Next specifically
    because Freestyle line rendering (the outline) is long-established and reliable there;
    Eevee Next's Freestyle support is newer and unverified as of Blender 5.2."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    # Blender 4.0+/5.x defaults view_transform to AgX, a photographic
    # tone-mapping curve that compresses/desaturates highlights — measured
    # directly on a real render: TRUNCHEON_COLOR (0.72, 0.18, 0.12) came out
    # as (172, 96, 77), nowhere near the ~(220, 117, 97) plain sRGB encoding
    # would produce, muting the rust-red/violet-purple role accents toward
    # brown while leaving cobalt-blue comparatively less affected — exactly
    # the "no red or purple, just light blue" the user flagged. flat_material()
    # feeds exact color values through Emission specifically so the output
    # should equal the input; Standard is the view transform that actually
    # does that, AgX is for photorealistic Cycles renders this pipeline
    # isn't doing.
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'

    scene.render.use_freestyle = True
    view_layer = bpy.context.view_layer
    view_layer.use_freestyle = True
    fs = view_layer.freestyle_settings
    if not fs.linesets:
        fs.linesets.new("Outline")
    lineset = fs.linesets[0]
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("OutlineStyle")
    lineset.linestyle.color = (0.0, 0.0, 0.0)
    lineset.linestyle.thickness = resolution * OUTLINE_THICKNESS_FRACTION


def add_camera(category: str, yaw_deg: float = 45.0, distance: float = 10.0, ortho_scale: float = 3.0):
    """Orthographic camera at the category's elevation, given yaw around the world
    Z axis (45 degrees matches every existing prompt's "isometric-ish" framing —
    that's the default single-shot angle), always aimed at the world origin — asset
    scripts should build their model centered on (0, 0, 0). yaw_deg is what
    render_directional_to() sweeps to produce multiple facings of the same model."""
    elevation = math.radians(CATEGORY_ELEVATION_DEG.get(category, 75.0))
    yaw = math.radians(yaw_deg)

    # Re-entrant: render_directional_to() calls this once per facing in the same
    # scene, so drop any camera/aim-target left over from the previous facing first.
    for stale_name in ("Camera", "AimTarget"):
        stale = bpy.data.objects.get(stale_name)
        if stale is not None:
            bpy.data.objects.remove(stale, do_unlink=True)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)

    x = distance * math.cos(elevation) * math.cos(yaw)
    y = distance * math.cos(elevation) * math.sin(yaw)
    z = distance * math.sin(elevation)
    cam_obj.location = (x, y, z)

    # Aim at origin: track-to constraint avoids hand-rolling the rotation matrix.
    track = cam_obj.constraints.new(type='TRACK_TO')
    empty = bpy.data.objects.new("AimTarget", None)
    empty.location = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(empty)
    track.target = empty
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'

    bpy.context.scene.camera = cam_obj
    return cam_obj


def add_flat_light():
    """Purely cosmetic — matches LIGHT_EULER so an interactive .blend viewer sees
    roughly what the toon shader fakes, but contributes nothing to the actual render:
    every surface uses flat_material()'s Emission-based toon shader below, which
    computes its own light direction as a shader-graph constant rather than sampling
    this object. Cycles still wants a light in the scene or the world background
    stays fully black outside the film-transparent alpha."""
    light_data = bpy.data.lights.new(name="Fill", type='SUN')
    light_data.energy = 1.0
    light_data.use_shadow = False
    light_obj = bpy.data.objects.new(name="Fill", object_data=light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = LIGHT_EULER


def _toon_light_direction() -> mathutils.Vector:
    """Direction TOWARD the light, for a NdotL dot product — the Sun's local +Z axis
    rotated by the same euler used for the (cosmetic) Sun object, so the fake
    terminator lines up with where add_flat_light()'s Sun actually points."""
    vec = mathutils.Vector((0.0, 0.0, 1.0))
    vec.rotate(mathutils.Euler(LIGHT_EULER, 'XYZ'))
    return vec


def flat_material(name: str, color, alpha: float = 1.0):
    """Cheap 2-tone toon shade: a hard-edged NdotL computed directly in the shader
    graph (Geometry normal dot a hardcoded light-direction constant, through a
    CONSTANT-interpolation ColorRamp) rather than sampled from a real light — cheap
    because it's pure vector math, no path-traced lighting pass involved, and
    deterministic across re-renders. Still routed through Emission so the render
    engine's own light sampling never touches it — only this shader graph decides
    the tone. Matches 'flat painterly cel-shading' (Style DNA) more literally than
    the flat single-tone version this replaced."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    geometry = nodes.new("ShaderNodeNewGeometry")

    light_dir = _toon_light_direction()
    light_vec = nodes.new("ShaderNodeCombineXYZ")
    light_vec.inputs[0].default_value = light_dir.x
    light_vec.inputs[1].default_value = light_dir.y
    light_vec.inputs[2].default_value = light_dir.z

    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    links.new(geometry.outputs["Normal"], dot.inputs[0])
    links.new(light_vec.outputs["Vector"], dot.inputs[1])

    # Dot product on two normalized vectors is [-1, 1]; remap to [0, 1] for the ramp.
    remap = nodes.new("ShaderNodeMath")
    remap.operation = 'MULTIPLY_ADD'
    remap.inputs[1].default_value = 0.5
    remap.inputs[2].default_value = 0.5
    links.new(dot.outputs["Value"], remap.inputs[0])

    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (TOON_SHADOW_MULT, TOON_SHADOW_MULT, TOON_SHADOW_MULT, 1.0)
    ramp.color_ramp.elements[1].position = TOON_TERMINATOR
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(remap.outputs["Value"], ramp.inputs["Fac"])

    tone_mix = nodes.new("ShaderNodeMix")
    tone_mix.data_type = 'RGBA'
    tone_mix.blend_type = 'MULTIPLY'
    tone_mix.inputs["Factor"].default_value = 1.0
    tone_mix.inputs["A"].default_value = (*color, alpha)
    links.new(ramp.outputs["Color"], tone_mix.inputs["B"])

    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 1.0
    links.new(tone_mix.outputs["Result"], emission.inputs["Color"])

    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def part(mesh_op, material, location, scale=None, rotation=None, **kwargs):
    """Shared boilerplate every character-model script's individual body
    part repeats: add a primitive, flat-shade it, assign its material,
    apply an optional scale/rotation. Pulled out once multiple unit
    scripts needed the exact same 5 lines (truncheoneer.py had it as a
    private copy first) rather than re-duplicating it per script."""
    mesh_op(location=location, **kwargs)
    obj = bpy.context.active_object
    if scale:
        obj.scale = scale
    if rotation:
        obj.rotation_euler = rotation
    bpy.ops.object.shade_flat()
    obj.data.materials.append(material)
    return obj


def curved_part(material, location, rotation, points, bevel_depth=0.02):
    """A Bezier-curve-based part, converted to mesh — for shapes plain
    primitives can't approximate well (a bow's arc, as opposed to a
    straight cylinder). `points` is a list of (x, y, z) control points in
    the part's own local space; AUTO handles give a smooth arc through
    them without hand-tuning bezier handle vectors."""
    curve_data = bpy.data.curves.new("CurvePart", type='CURVE')
    curve_data.dimensions = '3D'
    curve_data.bevel_depth = bevel_depth
    curve_data.bevel_resolution = 3
    spline = curve_data.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for i, point in enumerate(points):
        bp = spline.bezier_points[i]
        bp.co = point
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'

    obj = bpy.data.objects.new("CurvePart", curve_data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')  # So shade_flat()/materials work the same as every primitive-based part.
    bpy.ops.object.shade_flat()
    obj.data.materials.append(material)
    return obj


def sash(material, torso_location, torso_radius, diagonal_rotation=(0.35, 0.9, 0.0)):
    """A role-accent sash wrapping diagonally around a torso — a torus
    centered on the torso so it genuinely wraps all the way around (the
    far side is occluded by the body itself, same as a real sash would be
    from any single viewing angle, not a flat decal that only reads from
    one direction). `torso_radius` should roughly match the torso's own
    radius so the sash hugs its surface rather than floating clear of it
    or clipping inside it. Added after the user flagged the original
    weapon-only accent (Style DNA's old 2D-illustration convention) as too
    small to read at a glance once it's real 3D geometry instead of flat
    painted color."""
    part(bpy.ops.mesh.primitive_torus_add, material, torso_location,
         rotation=diagonal_rotation,
         major_radius=torso_radius + 0.02, minor_radius=torso_radius * 0.22)


def wheel(material, location, radius=0.15, thickness=0.09):
    """A vehicle wheel — cylinder axis along local X so it faces sideways
    (vehicles in this pipeline face +Y, same convention outrider.py's horse
    uses), shared by every Tier 4-5 vehicle script."""
    part(bpy.ops.mesh.primitive_cylinder_add, material, location,
         rotation=(0, 1.5708, 0), radius=radius, depth=thickness)


def gable_roof(material, location, width=0.7, depth=0.7, height=0.3, ridge_along_y=True):
    """A peaked roof — two angled planes meeting at a ridge, built from a
    scaled+rotated cube rather than a real wedge primitive (Blender has no
    single-call triangular-prism operator). ridge_along_y=True runs the
    ridge along the building's own front-back axis (gable ends face left/
    right); False runs it side to side (gable ends face front/back)."""
    rotation = (0.7854, 0, 0) if ridge_along_y else (0, 0.7854, 0)
    part(bpy.ops.mesh.primitive_cube_add, material, location,
         scale=(width, depth * 0.72, depth * 0.72) if ridge_along_y else (width * 0.72, depth, width * 0.72),
         size=1.0, rotation=rotation)


def chimney(material, location, height=0.4, radius=0.06):
    """A brick chimney stack — shared across most industrial buildings."""
    part(bpy.ops.mesh.primitive_cylinder_add, material, location, radius=radius, depth=height)
    part(bpy.ops.mesh.primitive_cylinder_add, material, (location[0], location[1], location[2] + height / 2.0 + 0.03),
         scale=(1.25, 1.25, 0.25), radius=radius, depth=0.05)  # Chimney cap, slightly wider.


def silo(material, location, radius=0.18, height=0.5):
    """A cylindrical grain/material silo with a domed top — agriculture and
    some industry buildings' signature accessory."""
    part(bpy.ops.mesh.primitive_cylinder_add, material, location, radius=radius, depth=height)
    part(bpy.ops.mesh.primitive_uv_sphere_add, material, (location[0], location[1], location[2] + height / 2.0),
         scale=(1.0, 1.0, 0.6), segments=10, ring_count=5, radius=radius)


def fence_perimeter(material, count=10, distance=0.85, post_height=0.16, post_radius=0.02):
    """A ring of thin fence posts around the building — matches the
    existing hand-illustrated buildings' own "fenced yard" convention
    (see assets/buildings/cast_iron_foundry.png). Cheap distinguishing
    silhouette detail shared by most industrial/agricultural buildings."""
    for i in range(count):
        angle = math.tau * i / count
        x = distance * math.cos(angle)
        y = distance * math.sin(angle)
        part(bpy.ops.mesh.primitive_cylinder_add, material, (x, y, post_height / 2.0),
             radius=post_radius, depth=post_height)


def render_to(output_path: str, category: str, resolution: int = 512):
    """Call once at the end of an asset script, after the model + materials exist."""
    setup_render(resolution)
    add_camera(category)
    add_flat_light()
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)


# 8-way facing, evenly spaced starting at the same 45-degree yaw the single-shot
# render uses as its default (so a unit's un-rotated "front" facing matches what its
# existing single-PNG art already looked like, minimizing visual churn when a unit
# gains directional facings). Order is compass-conventional (N first, clockwise) but
# which yaw_deg actually reads as "north" on screen depends on how the game's own
# hex-to-screen projection is oriented — NOT verified against that yet, flagged in
# tools/blender_pipeline/README.md as a decision for whoever wires this into
# TacticalEntityLayer, not guessed at here.
DIRECTIONS_8 = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


def render_directional_to(output_dir: str, key: str, category: str, resolution: int = 512):
    """Renders DIRECTIONS_8 facings of the same built model to
    <output_dir>/<key>_<direction>.png, reusing one Blender session (model built
    once, only the camera moves) rather than re-invoking Blender 8 times."""
    setup_render(resolution)
    add_flat_light()
    for i, direction in enumerate(DIRECTIONS_8):
        yaw_deg = 45.0 + i * (360.0 / len(DIRECTIONS_8))
        add_camera(category, yaw_deg=yaw_deg)
        bpy.context.scene.render.filepath = f"{output_dir}/{key}_{direction}.png"
        bpy.ops.render.render(write_still=True)
