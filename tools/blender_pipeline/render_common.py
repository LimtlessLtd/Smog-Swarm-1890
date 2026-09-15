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
    # Icons are HUD glyphs in a fixed box, never drawn on the map, so the
    # game's camera projection does not apply to them — they keep the shallow
    # 3/4 angle that stops a top-down lump reading as a blob at icon size
    # (icons/README.md's own reasoning).
    "icons": 55.0,
    # Every category below is drawn on the map, and the map is top-down. User
    # decision 2026-09-15: "transition to an entirely top down view, no more
    # isometric buildings on top down view" and, on the figures specifically,
    # "everything should be straight-down and if the models dont look good or
    # distinctive anymore then create new models that look distinctive from a
    # top down perspective".
    #
    # This is not a camera tweak. A model authored for an angled camera loses
    # everything vertical when the camera goes overhead — measured on the
    # pre-change art: town_hall rendered as two brown rectangles and a circle
    # (its clock face is vertical, so it vanished), terraced_tenement as four
    # plain brown rectangles. The models were re-authored to carry their
    # identity in the roof plan and footprint instead of the facade; see
    # hip_roof()/yard_plate() and the top-down figure rig below.
    "units": 90.0,
    "buildings": 90.0,
    "props": 90.0,
    # Was 35 (a "barrier FACE" side-on shot) — user correction (2026-08-17):
    # "the same should be true for walls and gates" as infrastructure, i.e.
    # top-down. The game itself never shows a wall from the side (WallVisuals
    # applies these as a Line2D-tiled texture on the flat 2D map, same as
    # every other overhead sprite) so a face-on render was inconsistent with
    # how the art actually gets used, not a deliberate stylistic exception.
    # A Gate segment has no separate art asset — WallVisuals.gate_color()
    # tints whichever tier texture is already in play, so re-rendering the 3
    # wall tier textures covers gates too.
    "walls": 90.0,
    "zombies": 90.0,  # Same reasoning as units.
    "terrain": 90.0,  # straight down — terrain tiles are flat-viewed, no side ever visible
    # Road/Railway/Canal/Bridge are flat line segments drawn along a hex
    # edge/path (SupplyLinePlacementController's hex-click-chain), not a
    # standalone object with a "face" — same reasoning as "terrain", not a
    # reused angled category.
    "infrastructure": 90.0,
}

# Extra per-category tightening of add_camera()'s default ortho_scale=3.0.
# "walls"/"infrastructure" models are long, thin strips (built ~1.0 unit
# long, ~0.1-0.2 wide) meant to be seen from directly above and tiled along
# their length by Line2D — framed at the same 3.0 scale every bodied
# category uses, the strip would occupy only a sliver of the square frame,
# starving the tiled texture of resolution. Anything not listed here keeps
# add_camera()'s own 3.0 default.
CATEGORY_ORTHO_SCALE = {
    "walls": 1.3,
    "infrastructure": 1.3,
}

# Freestyle thickness is in absolute render-resolution pixels, not a fraction of frame
# size — a 3px line was nearly invisible once downscaled to the 20x20 HUD icon size
# icons/README.md documents. Scale as a fraction of resolution instead so the outline
# stays "thick bold" (that README's own words) at whatever size the asset is actually
# displayed at in-game, not just at native render resolution.
# 0.018 -> 0.011 for the top-down move (2026-09-15). The old value was set
# against angled renders made of many small parts, where a heavy line held the
# silhouette together. A straight-down render is a few large flat shapes instead,
# and at 0.018 the stroke closed over real detail: on town_hall it swallowed the
# pale plinth course between the roof and the forecourt entirely, and on
# terraced_tenement it merged the chimney discs into their own outlines. Chosen
# by rendering 0.018/0.011/0.007 side by side — 0.007 is cleaner at native
# resolution but the line is what survives minification to the 17-46 px a figure
# actually occupies on screen, so the thinnest candidate is not the safe one.
OUTLINE_THICKNESS_FRACTION = 0.011

# Shared between add_flat_light() (cosmetic — the Sun object itself lights nothing,
# see flat_material()) and flat_material()'s toon shader, which needs the same
# direction baked in as a shader-graph constant so the fake NdotL terminator lines up
# with where a real light would actually be if anyone ever re-lit this scene for real.
LIGHT_EULER = (math.radians(55), 0.0, math.radians(35))

# Where the 2-tone terminator falls, in remapped-dot-product space (0.5 == exactly the
# geometric terminator).
#
# 0.42 -> 0.62 for the top-down move (2026-09-15). 0.42 corresponds to a dot
# product of -0.16, i.e. a surface stayed "lit" until it pointed more than 99
# degrees away from the light. That was survivable at an angled camera, where a
# model shows vertical faces pointing in every direction. At a straight-down
# camera almost every visible surface points broadly up, so all four planes of a
# hip_roof() cleared the threshold and every roof on the roster rendered as ONE
# flat tone with nothing but Freestyle creases drawn on it — the first top-down
# slice came out as a grey rectangle with a black X on it, on every building.
#
# 0.62 puts the threshold at dot >= 0.10, so a plane tilted away from the light
# falls into shadow: two roof planes lit, two in shadow, and a pyramid cap shows
# four distinct faces. Verified by rendering 0.42/0.55/0.62 side by side rather
# than derived — 0.55 was still too permissive to separate the long slopes.
TOON_TERMINATOR = 0.62
TOON_SHADOW_MULT = 0.55  # shadow tone = base color * this, not a flat gray — keeps hue


def reset_scene():
    """Start from a genuinely empty scene — no default cube/light/camera to forget to delete."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


NO_OUTLINE_COLLECTION = "NoOutline"


def no_outline_collection():
    """The collection setup_render()'s Freestyle lineset excludes. Created on
    demand because reset_scene() wipes the file, and build() runs before
    setup_render(), so either side may be the first to ask for it."""
    coll = bpy.data.collections.get(NO_OUTLINE_COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(NO_OUTLINE_COLLECTION)
        bpy.context.scene.collection.children.link(coll)
    return coll


def exclude_from_outline(obj):
    """Move `obj` into NO_OUTLINE_COLLECTION so Freestyle skips it."""
    coll = no_outline_collection()
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    coll.objects.link(obj)
    return obj


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
    # the "no red or purple, just light blue" the user flagged. Standard is the
    # view transform that leaves colour alone; AgX is for photorealistic Cycles
    # renders this pipeline isn't doing.
    #
    # Standard alone does NOT make output equal input, which this comment used
    # to claim: it drops AgX's tone curve but not the linear-to-sRGB encode, so
    # every authored colour still came out ~0.2 too light until
    # _srgb_to_linear() was added on the input side. See that function.
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

    # Everything in NO_OUTLINE_COLLECTION is exempt from the black stroke.
    #
    # The outline is what makes a shape read as a built object, and that is
    # exactly wrong for ground: a stroked yard slab reads as a hard-edged tile
    # laid on the terrain rather than as dirt. Until this existed the only way
    # to have ground at all was to accept a black border round it, which is why
    # every building looked like a square sticker, and why the figure drop
    # shadow had to be abandoned (it rendered as a ring).
    lineset.select_by_collection = True
    lineset.collection = no_outline_collection()
    lineset.collection_negation = 'EXCLUSIVE'


def add_camera(category: str, yaw_deg: float = None, distance: float = 10.0, ortho_scale: float = None):
    """Orthographic camera at the category's elevation, given yaw around the world
    Z axis (45 degrees matches every existing prompt's "isometric-ish" framing —
    that's the default single-shot angle for an angled category), always aimed at
    the world origin — asset scripts should build their model centered on
    (0, 0, 0). yaw_deg is what render_directional_to() sweeps to produce multiple
    facings of the same model. ortho_scale defaults to CATEGORY_ORTHO_SCALE's
    per-category framing, falling back to 3.0 (every bodied category's original
    hardcoded value) if the category isn't listed there — pass an explicit value
    to override either."""
    if ortho_scale is None:
        ortho_scale = CATEGORY_ORTHO_SCALE.get(category, 3.0)
    category_elevation_deg = CATEGORY_ELEVATION_DEG.get(category, 75.0)
    is_straight_down = abs(category_elevation_deg - 90.0) < 1e-6
    if yaw_deg is None:
        # A straight-down camera has no "isometric angling" for 45 to describe —
        # any nonzero yaw here just spins the whole image in-plane (measured: it
        # rotated wall_wooden.py's posts 45 degrees off horizontal). 0 keeps the
        # model's local X/Y mapped straight to image X/Y, matching every
        # walls/infrastructure script's own "built along local X" convention.
        yaw_deg = 0.0 if is_straight_down else 45.0
    elevation = math.radians(category_elevation_deg)
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

    if is_straight_down:
        # Straight-down (elevation == 90): TRACK_TO's up_axis has nothing to
        # solve for when the aim direction is exactly world -Z, producing an
        # arbitrary/inconsistent in-plane rotation — measured directly on
        # wall_wooden.py (posts built along local X, meant to render as a
        # horizontal row): the TRACK_TO path below rendered them as a
        # diagonal scatter instead. A direct rotation sidesteps the
        # constraint's singularity: a camera at identity rotation already
        # looks along -Z with local +X/+Y mapped straight to image X/Y, so a
        # model built along local X (every walls/infrastructure script's own
        # convention, matching WallVisuals/SupplyLineVisuals' length-axis
        # tiling) comes out with that axis horizontal, as intended.
        cam_obj.location = (0.0, 0.0, distance)
        cam_obj.rotation_euler = (0.0, 0.0, yaw)
    else:
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


# Fraction of the fitted frame left empty on EACH side by frame_content().
# Not cosmetic padding: the Freestyle outline is stroked along the silhouette
# at OUTLINE_THICKNESS_FRACTION of the render resolution and is centered on
# that edge, so about half its width falls outside the geometry bounds this
# fit is computed from. Fitting the geometry exactly would shave the outline
# off wherever the model touches the frame edge. 0.04 covers half of a 0.018
# stroke with room left for Cycles' antialiasing.
CONTENT_MARGIN_FRACTION = 0.04


def content_bounds(cam_obj):
    """(min_x, max_x, min_y, max_y) of every mesh vertex in the scene, expressed
    in the camera's own view plane. None if the scene has no mesh geometry.

    Real vertices rather than each object's bound_box: a bound_box is the
    object's LOCAL axis-aligned box, and transforming its 8 corners bounds a
    rotated object only loosely — gable_roof() and sash() are both 45-degree-ish
    rotated primitives, which is exactly the case that over-estimates."""
    view = cam_obj.matrix_world.inverted()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    xs, ys = [], []
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        matrix = view @ evaluated.matrix_world
        for vertex in mesh.vertices:
            point = matrix @ vertex.co
            xs.append(point.x)
            ys.append(point.y)
        evaluated.to_mesh_clear()
    if not xs:
        return None
    return min(xs), max(xs), min(ys), max(ys)


def frame_content(cam_obj, ortho_scale: float = None) -> float:
    """Re-aim the camera at the content's own centre and size the frame to it.
    Returns the content's span in world units (the un-margined ortho_scale that
    would fit it), so a caller can measure without rendering.

    add_camera() always aims at the world origin at a fixed ortho_scale=3.0,
    which framed every asset by where its author happened to build it rather
    than by how big it is. Measured across the shipped art before this existed:
    a building filled 23.6-48.6% of the frame's longest side and a resource icon
    15.1-45.9%, so a 2048x2048 icon scaled into ResourceBarView's 20x20 slot was
    delivering a ~3px glyph.

    Pass ortho_scale to frame at a fixed size instead of this model's own —
    that is how a whole category keeps its authored relative sizes (every asset
    centred, one shared frame size) rather than every asset being blown up to
    fill the frame equally and a watchtower ending up as wide as a farm."""
    # add_camera()'s angled path aims via a TRACK_TO constraint, which re-solves
    # the rotation from wherever the camera currently IS — so translating the
    # camera with it still attached just swings it back onto the world origin
    # and undoes the centring. Bake the constraint's solved orientation into the
    # camera's own transform first, then drop it; an ortho camera that already
    # points the right way needs no aim target, and its framing then depends
    # only on where it sits in its own view plane.
    bpy.context.view_layer.update()  # resolve TRACK_TO before reading matrix_world
    solved = cam_obj.matrix_world.copy()
    for constraint in list(cam_obj.constraints):
        cam_obj.constraints.remove(constraint)
    cam_obj.matrix_world = solved

    bounds = content_bounds(cam_obj)
    if bounds is None:
        return cam_obj.data.ortho_scale
    min_x, max_x, min_y, max_y = bounds

    # Content is NOT centred to begin with: an angled camera projects a model
    # built around the world origin well below frame centre, which is why
    # searchlight_tower's ink sat at y=585 of 2048 rather than straddling 1024.
    basis = cam_obj.matrix_world.to_3x3()
    cam_obj.location += basis @ mathutils.Vector(
        ((min_x + max_x) / 2.0, (min_y + max_y) / 2.0, 0.0))

    span = max(max_x - min_x, max_y - min_y)
    cam_obj.data.ortho_scale = (span if ortho_scale is None else ortho_scale) * (
        1.0 + 2.0 * CONTENT_MARGIN_FRACTION)
    return span


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


def _srgb_to_linear(color):
    """Treat an asset script's colour tuple as sRGB and convert to the linear
    values Blender's shader graph actually works in.

    Without this the pipeline could not author a dark colour at all, which is a
    measurable fact rather than a preference. Blender emits linear and the PNG
    is written sRGB-encoded, so a tuple typed as 0.145 came out of the renderer
    at 0.416 — exactly sRGB(0.145), confirmed by sampling truncheoneer's helmet
    (authored 0.145 -> rendered 106/255) and rifleman's shako (0.105 -> 91/255).
    Every value below about 0.5 landed more than 0.2 too light, so the bottom
    half of the tonal range was unreachable: "near-black" coats rendered as mid
    grey, which is a large part of why the whole roster read as washed-out and
    interchangeable, and why darkening the heavy-industry plate to 0.17 in an
    earlier pass visibly did nothing.

    setup_render()'s own comment claimed 'the output should equal the input'
    because view_transform is Standard. Standard is necessary for that and not
    sufficient — it removes AgX's tone curve but not the linear-to-sRGB encode.
    This closes the other half.

    Consequence for anyone editing an asset script: colour tuples are sRGB, i.e.
    what you type is what lands in the PNG. Constants written before 2026-09-15
    were tuned against the old lighter output, so re-check any that were not
    re-authored for the top-down pass.
    """
    out = []
    for channel in color:
        channel = max(0.0, min(1.0, float(channel)))
        if channel <= 0.04045:
            out.append(channel / 12.92)
        else:
            out.append(((channel + 0.055) / 1.055) ** 2.4)
    return tuple(out)


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
    tone_mix.inputs["A"].default_value = (*_srgb_to_linear(color), alpha)
    links.new(ramp.outputs["Color"], tone_mix.inputs["B"])

    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 1.0
    links.new(tone_mix.outputs["Result"], emission.inputs["Color"])

    output = nodes.new("ShaderNodeOutputMaterial")

    if alpha >= 1.0:
        links.new(emission.outputs["Emission"], output.inputs["Surface"])
        return mat

    # `alpha` was a dead parameter until 2026-09-15: it was written into the
    # 4th component of a COLOUR socket, which an Emission chain never reads, so
    # every call asking for transparency silently rendered fully opaque. Real
    # transparency needs a shader-level mix, which is what ground_patch() and
    # path() depend on to let terrain show through a building's footprint.
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    mix_shader = nodes.new("ShaderNodeMixShader")
    mix_shader.inputs["Fac"].default_value = alpha  # 0 -> fully transparent, 1 -> fully emissive
    links.new(transparent.outputs["BSDF"], mix_shader.inputs[1])
    links.new(emission.outputs["Emission"], mix_shader.inputs[2])
    links.new(mix_shader.outputs["Shader"], output.inputs["Surface"])
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


# --- Building family palette -------------------------------------------------
#
# Overhead, a building is a ground plate with a roof on it. Those two colours are
# most of what the player sees, so they are assigned per FAMILY here rather than
# picked per building script — 42 independently-chosen brown roofs is how the
# pre-top-down roster ended up with six buildings that read as the same box.
#
# Plate hues are spread around the wheel (cream / cobble grey / field green /
# ochre / ash / concrete / olive / gravel) so two families never share a ground
# tone, and each family's SIGNATURE (listed per entry) is a shape only that
# family uses. Per-building identity is then the arrangement and count of those
# signature pieces, not another colour.
BUILDING_FAMILY = {
    # plate, roof, accent
    "civic":      ((0.780, 0.727, 0.616), (0.286, 0.318, 0.372), (0.855, 0.671, 0.239)),
    "housing":    ((0.474, 0.463, 0.451), (0.541, 0.271, 0.196), (0.800, 0.780, 0.740)),
    "agriculture": ((0.514, 0.580, 0.259), (0.647, 0.322, 0.204), (0.870, 0.820, 0.640)),
    "extraction": ((0.545, 0.447, 0.302), (0.325, 0.267, 0.204), (0.140, 0.130, 0.125)),
    # Heavy's plate is much darker than the other families' (0.31 -> 0.17): at
    # 0.31 the ash plate, the iron sheds and the slate roofs were all mid-greys
    # within about 0.1 of each other and the whole building read as one grey
    # mass. The structures sit on top of it, so the plate is what has to give.
    "heavy":      ((0.170, 0.163, 0.157), (0.365, 0.380, 0.404), (0.910, 0.451, 0.110)),
    "power":      ((0.639, 0.631, 0.604), (0.290, 0.302, 0.325), (0.361, 0.706, 0.831)),
    "military":   ((0.435, 0.427, 0.318), (0.192, 0.278, 0.212), (0.690, 0.180, 0.150)),
    "logistics":  ((0.427, 0.427, 0.443), (0.290, 0.278, 0.263), (0.780, 0.620, 0.220)),
}

# Family signatures — the shape vocabulary each family owns exclusively.
#   civic       pyramid-capped tower + gold finial, entrance steps
#   housing     a ROW of parallel hip roofs, paired chimney discs per bay
#   agriculture furrow stripes on the plate, domed silo circle
#   extraction  headframe wheel (large ring) over a black shaft square, spoil heaps
#   heavy       glowing accent circle (furnace/tap hole) + large chimney discs
#   power       cooling-tower annulus (ring with a dark centre)
#   military    parade square inset in the plate + a red flag disc
#   logistics   parallel rail lines crossing the whole plate


def family_materials(family: str):
    """(plate_mat, roof_mat, accent_mat) for a BUILDING_FAMILY key."""
    plate, roof, accent = BUILDING_FAMILY[family]
    return (flat_material("Plate", plate),
            flat_material("Roof", roof),
            flat_material("Accent", accent))


def ground_stripe(material, centre, length, thickness, z=0.006, horizontal=True,
                  name="GroundStripe"):
    """One flat marking laid on the ground — a furrow, a rail, a painted line.

    Flat and outline-exempt, both deliberately. Built as a raised cube and left
    in the outline, a strip this thin is narrower than the Freestyle stroke that
    surrounds it, so it renders as a solid BLACK bar whatever colour it was
    given — which is what turned estate_farm's ploughing into a set of heavy
    black lines running across the field.
    """
    half_l, half_t = length / 2.0, thickness / 2.0
    cx, cy = centre
    if horizontal:
        verts = [(cx - half_l, cy - half_t, z), (cx + half_l, cy - half_t, z),
                 (cx + half_l, cy + half_t, z), (cx - half_l, cy + half_t, z)]
    else:
        verts = [(cx - half_t, cy - half_l, z), (cx + half_t, cy - half_l, z),
                 (cx + half_t, cy + half_l, z), (cx - half_t, cy + half_l, z)]
    return exclude_from_outline(_mesh_from(material, name, verts, [(0, 1, 2, 3)]))


def furrows(material, count=7, width=0.86, z=0.006, spacing=0.10, x=0.0,
            thickness=0.022):
    """Parallel ploughed lines on a field — the agriculture family signature.
    `x` centres the run, so a farm with a yard on one side keeps its ploughing
    clear of it."""
    made = []
    start = -(count - 1) * spacing / 2.0
    for i in range(count):
        made.append(ground_stripe(material, (x, start + i * spacing), width,
                                  thickness, z=z, name="Furrow%d" % i))
    return made


def rail_lines(material, count=3, length=1.2, z=0.008, spacing=0.16, thickness=0.026):
    """Parallel rails across a yard — the logistics family signature."""
    made = []
    start = -(count - 1) * spacing / 2.0
    for i in range(count):
        made.append(ground_stripe(material, (0.0, start + i * spacing), length,
                                  thickness, z=z, name="Rail%d" % i))
    return made


def headframe(timber_material, shaft_material, centre, shaft_half=0.14,
              wheel_outer=0.19, name="Headframe"):
    """Winding gear over a shaft — the extraction family's signature.

    Overhead this is a ring inside a dark square with four spokes running to the
    corners, which is a specific enough shape that a mine never reads as a shed.
    Shared rather than repeated per mine so the whole family says "mine" the same
    way, and only the ore colour and the layout around it vary.
    """
    cx, cy = centre
    part(bpy.ops.mesh.primitive_cube_add, shaft_material, (cx, cy, 0.030),
         scale=(shaft_half * 2.0, shaft_half * 2.0, 0.03), size=1.0)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part(bpy.ops.mesh.primitive_cube_add, timber_material,
             (cx + dx * shaft_half, cy + dy * shaft_half, 0.16),
             scale=(0.034, 0.034, 0.32), size=1.0)
    ring(timber_material, (cx, cy, 0.34), outer=wheel_outer, thickness=0.034, height=0.05)
    for i in range(4):
        part(bpy.ops.mesh.primitive_cube_add, timber_material, (cx, cy, 0.345),
             scale=(wheel_outer * 1.7, 0.021, 0.015), size=1.0,
             rotation=(0.0, 0.0, i * 0.7854))


def spoil_heaps(ore_material, positions, base_radius=0.15, step=0.02):
    """Cones of extracted material. Their COLOUR is what separates one mine from
    another across the extraction family — coal black, iron rust, sulfur yellow,
    clay ochre — so the heaps are always the most saturated thing on the site."""
    for i, (hx, hy) in enumerate(positions):
        part(bpy.ops.mesh.primitive_cone_add, ore_material, (hx, hy, 0.06),
             radius1=max(0.06, base_radius - i * step), radius2=0.0, depth=0.12)


def ring(material, location, outer=0.30, thickness=0.06, height=0.10):
    """A flat annulus — the power family's cooling tower from overhead, and the
    extraction family's headframe wheel. Built as a torus scaled flat so the
    silhouette is two concentric Freestyle circles, which is the most
    recognisable thing a straight-down camera can draw."""
    return part(bpy.ops.mesh.primitive_torus_add, material, location,
                scale=(1.0, 1.0, height / thickness),
                major_radius=outer - thickness, minor_radius=thickness)


# --- Top-down figure rig -----------------------------------------------------
#
# A figure rendered at CATEGORY_ELEVATION_DEG == 90 shows shoulders, head and
# whatever projects past them. It does NOT show a torso front, legs, a stance or
# a facial feature, so none of those can carry identity any more. Measured on the
# pre-top-down art at its real on-screen size (17 px at the MEDIUM/HIGH
# threshold, 46 px at max_zoom): all 18 units read as the same grey smudge
# because every coat was near-black and the role accent sat on a weapon worth
# under 5% of the sprite's pixels.
#
# The replacement encodes identity three times over, so it survives minification:
#   role  -> coat HUE           (the largest surface, not the weapon)
#   tier  -> coat VALUE + pips  (role_coat_color()'s ramp, plus rank_pips())
#   unit  -> silhouette         (headgear shape + what projects past the shoulders)
#
# Role hues are the ones the per-unit scripts already used for their weapon
# accents, moved onto the coat rather than re-chosen: the colour coding is the
# same, it is just applied where it can be seen.
#
# No ground-shadow ellipse, deliberately. The obvious way to stop an overhead
# figure floating on the terrain behind it is a dark disc under it, and that was
# tried first — but Freestyle strokes every silhouette it finds, including the
# disc's, so each unit rendered sitting in a hard black ring that read as a base
# plate or a crater. Excluding one object from Freestyle needs a face-mark lineset
# the rest of the pipeline does not use, and the figure's own outline already
# separates it from terrain, so the disc is simply gone.

ROLE_MELEE = (0.50, 0.03, 0.05)    # deep red
ROLE_RANGED = (0.05, 0.10, 0.45)   # deep blue
ROLE_SPECIAL = (0.30, 0.03, 0.42)  # deep purple

# Tier 0-3 are people; tiers 4-5 are vehicles and use the hue directly on
# hull panels instead of a coat. Tier controls two things at once: overall VALUE
# (a Tier 0 coat is dark) and SATURATION (a Tier 0 coat is dirty, a Tier 3 coat
# near-pure), because value alone did not separate the tiers enough to read.
# Retuned once _srgb_to_linear() landed: before it, everything rendered about
# 0.2 lighter than authored, so these were set low to compensate without anyone
# knowing that was what they were doing.
_TIER_VALUE = (0.55, 0.66, 0.80, 0.95, 1.00, 1.00)
_TIER_DESATURATE = (0.34, 0.25, 0.15, 0.06, 0.05, 0.05)


def role_coat_color(role_rgb, tier: int):
    """The coat colour for a (role, tier) pair: role_rgb's hue at a tier-dependent
    value and saturation. Tier 0 is a dark, dirty version of the role hue and
    Tier 3 near its pure form, so a Truncheoneer and a Highlander are obviously
    the same red family at obviously different ranks.

    The hue is normalised to its own peak channel FIRST, then scaled. Adding a
    flat lift to all three channels instead — the first version of this — raises
    the two minor channels as much as the dominant one, which is desaturation by
    another name: it turned Tier 0 melee into a dusty pink rather than a dark
    brick, measured on a real render.
    """
    index = max(0, min(tier, len(_TIER_VALUE) - 1))
    value = _TIER_VALUE[index]
    desaturate = _TIER_DESATURATE[index]
    peak = max(role_rgb)
    normalised = [channel / peak for channel in role_rgb]
    grey = sum(normalised) / 3.0
    return tuple(
        min(1.0, (channel * (1.0 - desaturate) + grey * desaturate) * value)
        for channel in normalised
    )


def role_panel_color(role_rgb, tier: int, toward=(0.243, 0.231, 0.216), amount=0.34):
    """The role hue for a VEHICLE hull panel: role_coat_color() knocked back
    toward the hull grey.

    Tiers 4-5 sit at the top of the tier ramp, so a coat colour applied straight
    to a machine comes out at near-pure hue — rendered, the Tier 5 vehicles were
    neon red and magenta against a building roster that is all soot, brick and
    olive. A painted steel panel is a knocked-back version of a dress-uniform
    colour, not the same colour, and mixing toward the hull keeps the role
    readable while letting the machines sit in the same world as everything else.
    """
    base = role_coat_color(role_rgb, tier)
    return tuple(base[i] * (1.0 - amount) + toward[i] * amount for i in range(3))


def bone(material, start, end, radius, name="Bone"):
    """A cylinder spanning exactly `start` to `end`.

    Placing limb segments by eye — a cylinder at a guessed midpoint with a
    guessed euler — is what produced arms that did not meet their own shoulders
    or hands ("theres arms and hands that arent properly joined up", user,
    2026-09-15). Here the endpoints ARE the input, so a limb cannot float free of
    its joint however the pose changes.
    """
    a = mathutils.Vector(start)
    b = mathutils.Vector(end)
    direction = b - a
    length = direction.length
    if length < 1e-6:
        return None
    rotation = direction.to_track_quat('Z', 'Y').to_euler()
    return part(bpy.ops.mesh.primitive_cylinder_add, material,
                tuple((a + b) / 2.0),
                rotation=(rotation.x, rotation.y, rotation.z),
                radius=radius, depth=length)


def limb(material, joints, radii, joint_material=None, segments=8):
    """An articulated chain: a bone between each pair of joints, and a sphere AT
    every joint sized to the thicker of the two bones meeting there.

    The joint spheres are not decoration. Two cylinders meeting at an angle leave
    a wedge-shaped gap on the outside of the bend, which from directly overhead
    reads as a broken arm; the sphere fills it and doubles as the shoulder ball,
    elbow and wrist. `radii` is per BONE, so len(radii) == len(joints) - 1.
    """
    joint_material = joint_material or material
    made = []
    for i in range(len(joints) - 1):
        made.append(bone(material, joints[i], joints[i + 1], radii[i]))
    for i, joint in enumerate(joints):
        radius = max(radii[max(0, i - 1)], radii[min(i, len(radii) - 1)])
        made.append(part(bpy.ops.mesh.primitive_uv_sphere_add, joint_material,
                         joint, segments=segments, ring_count=max(4, segments // 2),
                         radius=radius * 1.06))
    return made


def hand(material, location, radius=0.040, spread=0.0, fingers=0, facing=0.0):
    """A hand: a palm sphere, optionally with finger stubs fanned from it.

    `fingers` 0 gives a closed fist (a soldier gripping a weapon); 3 with a
    spread gives a clawed reach (a zombie). Fingers are what stop a limb ending
    in a blunt ball, which was the other half of the "not properly joined up"
    read — an arm that simply stops looks unfinished at close zoom.
    """
    made = [part(bpy.ops.mesh.primitive_uv_sphere_add, material, location,
                 segments=10, ring_count=6, radius=radius)]
    for i in range(fingers):
        angle = facing + (i - (fingers - 1) / 2.0) * spread
        tip = (location[0] + math.sin(angle) * radius * 2.1,
               location[1] + math.cos(angle) * radius * 2.1,
               location[2])
        made.append(bone(material, location, tip, radius * 0.34))
        made.append(part(bpy.ops.mesh.primitive_uv_sphere_add, material, tip,
                         segments=6, ring_count=4, radius=radius * 0.34))
    return made


# --- Soldier rig -------------------------------------------------------------
#
# Height is invisible from straight down, so Z is not depth — it is DRAW ORDER,
# and it has to be laid out deliberately. The first version of this rig put the
# arms on the torso's own centre plane, where the shoulder mass occluded them
# completely: every joint rendered correctly and none of it was visible.
#
# These four planes are the contract. Anything an asset script adds should be
# placed relative to one of them rather than by eye.
FIGURE_Z = 0.30                      # torso centre
FIGURE_TORSO_TOP = FIGURE_Z + 0.112  # top of the coat
FIGURE_TRIM_Z = FIGURE_TORSO_TOP + 0.008   # interior trim: visible, cannot widen the outline
FIGURE_ARM_Z = FIGURE_TORSO_TOP + 0.030    # arms ride above the coat
FIGURE_HAND_Z = FIGURE_ARM_Z
FIGURE_WEAPON_Z = FIGURE_ARM_Z + 0.022


def soldier_boots(material, spread=0.105, back=-0.165, length=0.082):
    """Two boot toes showing from under the coat. Overlapped by the torso on
    purpose — a boot drawn clear of the body reads as a detached blob."""
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_uv_sphere_add, material,
             (side * spread, back, 0.045), rotation=(0.0, 0.0, side * 0.24),
             scale=(0.052, length, 0.028), segments=10, ring_count=6, radius=1.0)


def soldier_torso(material, shoulder_half=0.150, width=0.215, depth=0.135,
                  chest_forward=0.065, bulk=1.0):
    """Shoulder mass plus a chest forward of it, returning the two shoulder
    joints for soldier_arms() to hang off.

    Three overlapping domes rather than one oval: the pair of shoulder blobs
    leaves a neck notch for the head to sit in, which is what makes a head read
    as a head instead of as a button on a blob. `bulk` scales the whole thing so
    a greatcoat reads heavier than a shirtsleeved navvy without re-authoring it.
    """
    part(bpy.ops.mesh.primitive_uv_sphere_add, material, (0.0, -0.015, FIGURE_Z),
         scale=(width * bulk, depth * bulk, 0.112), segments=18, ring_count=9, radius=1.0)
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_uv_sphere_add, material,
             (side * shoulder_half * bulk, -0.005, FIGURE_Z),
             rotation=(0.0, 0.0, side * -0.30),
             scale=(0.105 * bulk, 0.135 * bulk, 0.104), segments=14, ring_count=8, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, material, (0.0, chest_forward, FIGURE_Z),
         scale=(0.145 * bulk, 0.140 * bulk, 0.106), segments=16, ring_count=8, radius=1.0)
    reach = (shoulder_half + 0.045) * bulk
    return ((-reach, -0.015, FIGURE_ARM_Z), (reach, -0.015, FIGURE_ARM_Z))


def soldier_arm(sleeve_material, cuff_material, skin_material, shoulder, hand_at,
                elbow_out=0.075, elbow_forward=0.095, radius=0.050, fingers=0,
                brass_material=None):
    """One arm from `shoulder` to `hand_at`, via an elbow placed outboard of the
    straight line between them.

    The elbow is DERIVED rather than authored so an arm can never be posed into
    a straight plank or a broken angle, whatever weapon grip a unit uses — the
    caller only says where the hand goes.
    """
    side = 1.0 if shoulder[0] >= 0.0 else -1.0
    mid = ((shoulder[0] + hand_at[0]) / 2.0, (shoulder[1] + hand_at[1]) / 2.0, FIGURE_ARM_Z)
    elbow = (mid[0] + side * elbow_out, mid[1] + elbow_forward, FIGURE_ARM_Z)
    limb(sleeve_material, [shoulder, elbow, hand_at], [radius, radius * 0.86])
    cuff = tuple(hand_at[i] + (elbow[i] - hand_at[i]) * 0.22 for i in range(3))
    part(bpy.ops.mesh.primitive_uv_sphere_add, cuff_material, cuff,
         segments=10, ring_count=6, radius=radius * 0.92)
    if brass_material is not None:
        part(bpy.ops.mesh.primitive_cylinder_add, brass_material,
             (cuff[0], cuff[1], cuff[2] + radius * 0.84), vertices=8,
             radius=0.009, depth=0.008)
    hand(skin_material, hand_at, radius=0.042, fingers=fingers, spread=0.5)
    return elbow


def soldier_head(material, *, radius=0.090, height=0.12, forward=0.105,
                 peak=None, band_material=None, badge_material=None,
                 collar_material=None):
    """Headgear as a cylinder with optional peak, band and badge.

    Headgear is the largest circle in a top-down figure and therefore the
    cheapest per-unit differentiator there is — a flat cap is small and low, a
    slouch hat wide, a mitre tall and narrow, a feather bonnet large. Vary
    `radius` first when separating two units of the same role.

    The band is a TORUS, not a disc: a full-radius cream lid made the head the
    brightest, largest shape on the figure and it read as a white ball.
    """
    if collar_material is not None:
        part(bpy.ops.mesh.primitive_uv_sphere_add, collar_material,
             (0.0, forward, FIGURE_ARM_Z + 0.02), scale=(0.080, 0.072, 0.040),
             segments=12, ring_count=6, radius=1.0)
    crown_z = FIGURE_ARM_Z + 0.10
    part(bpy.ops.mesh.primitive_cylinder_add, material, (0.0, forward, crown_z),
         vertices=14, radius=radius, depth=height)
    if peak:
        part(bpy.ops.mesh.primitive_cube_add, material,
             (0.0, forward + peak, crown_z - 0.038),
             scale=(radius * 1.53, 0.082, 0.018), size=1.0)
    top = crown_z + height / 2.0
    if band_material is not None:
        part(bpy.ops.mesh.primitive_torus_add, band_material, (0.0, forward, top - 0.002),
             major_radius=radius, minor_radius=0.013)
        part(bpy.ops.mesh.primitive_cylinder_add, material, (0.0, forward, top + 0.002),
             vertices=14, radius=radius * 0.91, depth=0.012)
    if badge_material is not None:
        part(bpy.ops.mesh.primitive_cylinder_add, badge_material,
             (0.0, forward + radius * 0.48, top + 0.008), vertices=8,
             radius=radius * 0.26, depth=0.008)
    return top


def soldier_trim(coat_light, coat_dark, belt_material, brass_material, *,
                 buttons=3, waist_belt=True, pouch=True, cross_belts=True,
                 shoulder_half=0.150):
    """Interior coat detail — chest panel, shoulder straps, buttons, waist belt
    and buckle, ammunition pouch, cross-belts and their plate.

    All of it sits between FIGURE_TRIM_Z and FIGURE_TORSO_TOP, i.e. above the
    coat and below the arms, so it CANNOT widen the silhouette. That is the
    whole point: the user's brief was "a bit more detail but leaving the
    distinctive outline", so detail is confined to a plane where it is
    structurally unable to affect the outline.
    """
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_light, (0.0, 0.058, FIGURE_TRIM_Z - 0.005),
         scale=(0.100, 0.108, 0.014), segments=14, ring_count=7, radius=1.0)
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cube_add, coat_dark,
             (side * (shoulder_half - 0.015), 0.005, FIGURE_TRIM_Z),
             rotation=(0.0, 0.0, side * -0.30), scale=(0.048, 0.115, 0.010), size=1.0)
    for row in (-1.0, 1.0):
        for i in range(buttons):
            part(bpy.ops.mesh.primitive_cylinder_add, brass_material,
                 (row * 0.030, 0.022 + i * 0.040, FIGURE_TRIM_Z + 0.006),
                 vertices=8, radius=0.0105, depth=0.008)
    if waist_belt:
        part(bpy.ops.mesh.primitive_cube_add, coat_dark, (0.0, -0.090, FIGURE_TRIM_Z),
             scale=(0.230, 0.030, 0.010), size=1.0)
        part(bpy.ops.mesh.primitive_cylinder_add, brass_material, (0.0, -0.090, FIGURE_TRIM_Z + 0.006),
             vertices=8, radius=0.016, depth=0.008)
    if pouch:
        part(bpy.ops.mesh.primitive_cube_add, coat_dark, (0.112, -0.094, FIGURE_TRIM_Z + 0.008),
             rotation=(0.0, 0.0, 0.18), scale=(0.060, 0.046, 0.012), size=1.0)
    if cross_belts:
        for angle in (0.72, -0.72):
            part(bpy.ops.mesh.primitive_cube_add, belt_material, (0.0, 0.015, FIGURE_TORSO_TOP + 0.004),
                 rotation=(0.0, 0.0, angle), scale=(0.034, 0.255, 0.012), size=1.0)
        part(bpy.ops.mesh.primitive_cylinder_add, brass_material, (0.0, 0.015, FIGURE_TORSO_TOP + 0.013),
             vertices=10, radius=0.027, depth=0.008)


def soldier_pack(coat_dark, belt_material, back=-0.150, width=0.132):
    """The knapsack, tucked under the shoulder mass so it reads as worn rather
    than as a second object parked behind the figure."""
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_dark, (0.0, back, FIGURE_Z - 0.010),
         scale=(width, 0.098, 0.090), segments=14, ring_count=8, radius=1.0)
    part(bpy.ops.mesh.primitive_cube_add, belt_material, (0.0, back - 0.018, FIGURE_TORSO_TOP - 0.020),
         scale=(width * 0.98, 0.030, 0.010), size=1.0)


def along(a, b, t):
    """Point `t` of the way from `a` to `b`. Used to hang hands and weapon
    furniture off a single declared weapon axis, so a grip cannot drift off the
    thing it is supposed to be gripping."""
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _mesh_from(material, name, verts, faces, location=(0.0, 0.0, 0.0)):
    """Build an explicit-geometry mesh object. Primitives cannot express a
    hipped roof, and every top-down building silhouette depends on one."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.materials.append(material)
    return obj


def hip_roof(material, location, width=0.7, depth=0.7, height=0.22, ridge_fraction=0.45,
             name="HipRoof"):
    """A four-plane hipped roof: two trapezoid slopes meeting at a ridge, two
    triangular hips closing the ends.

    This is the load-bearing shape for the top-down camera. gable_roof() has two
    planes that share one horizontal normal component, so from directly overhead
    (CATEGORY_ELEVATION_DEG["buildings"] == 90) it projects to a plain rectangle
    split by a single line — measured on the pre-top-down town_hall, which
    rendered as two brown rectangles. A hip has four planes facing four different
    compass directions, so flat_material()'s NdotL splits them into lit/shadow
    pairs AND Freestyle strokes the ridge plus all four hip edges as creases. The
    result reads as a roof from overhead instead of as a flat slab.

    `ridge_fraction` is the ridge's half-length as a fraction of half-width: 0.0
    is a pyramid (right for towers), ~0.45 a normal hall, 1.0 degenerates back to
    a gable. width/depth are full extents; the roof sits centred on `location`
    with its eaves at that Z.
    """
    hw = width / 2.0
    hd = depth / 2.0
    rx = hw * ridge_fraction
    verts = [
        (-hw, -hd, 0.0), (hw, -hd, 0.0), (hw, hd, 0.0), (-hw, hd, 0.0),
        (-rx, 0.0, height), (rx, 0.0, height),
    ]
    faces = [
        (0, 1, 5, 4),  # slope facing -Y
        (2, 3, 4, 5),  # slope facing +Y
        (1, 2, 5),     # hip facing +X
        (3, 0, 4),     # hip facing -X
        (3, 2, 1, 0),  # underside, so the eaves read as a closed edge
    ]
    obj = _mesh_from(material, name, verts, faces, location)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


# --- Organic ground --------------------------------------------------------
#
# User note, 2026-09-15, on the first top-down slice: the buildings "are all
# exact squares with no transparency anywhere, i think they should look more
# natural and blend better with the terrain e.g. using transparency and paths
# between the various different buildings within 1 building image asset".
#
# The cause was yard_plate(): one opaque full-quad slab per building, stroked
# black by Freestyle, so every asset was a hard rectangle pasted over the
# terrain. The replacement has three parts, and all three are needed:
#
#   ground_patch()  irregular blobs under each structure instead of one
#                   rectangle, so the footprint's edge is ragged and the gaps
#                   between them are genuinely transparent -> terrain shows
#   path()          tracks joining the structures, which is what the user
#                   asked for directly and also what stops a scatter of
#                   patches reading as unrelated debris
#   alpha           patches are laid at alpha < 1 so terrain tone bleeds
#                   through rather than being replaced (needs flat_material()'s
#                   alpha fix, which was a no-op until now)
#
# Both helpers exclude themselves from the outline. Ground with a black border
# is the square-sticker problem again at a smaller scale.


def _hash01(seed: int, index: int) -> float:
    """Deterministic pseudo-random in [0,1). Not random.random(): a re-render
    must produce a byte-identical PNG, and the 8 facings of one model must agree
    on where the ragged edges are or the ground would crawl as a unit turns."""
    value = math.sin(seed * 127.1 + index * 311.7) * 43758.5453
    return value - math.floor(value)


def ground_patch(material, location=(0.0, 0.0, 0.0), radius_x=0.40, radius_y=0.35,
                 sides=13, jitter=0.24, seed=0, name="GroundPatch"):
    """An irregular ground blob — dirt, spoil, hardstanding, worn grass.

    A single flat n-gon with per-vertex radius jitter. Flat rather than a slab
    because the camera is straight down and no side face can ever be seen, and
    because two overlapping slabs z-fight where a patch meets a path.
    """
    verts = []
    for i in range(sides):
        angle = math.tau * i / sides
        scale = 1.0 + (_hash01(seed, i) - 0.5) * 2.0 * jitter
        verts.append((location[0] + math.cos(angle) * radius_x * scale,
                      location[1] + math.sin(angle) * radius_y * scale,
                      location[2]))
    obj = _mesh_from(material, name, verts, [tuple(range(sides))])
    return exclude_from_outline(obj)


def path(material, points, width=0.10, z=0.006, jitter=0.22, seed=0, name="Path"):
    """A worn track through a site, as a ribbon along `points` (a list of (x, y)).

    Width wobbles per point so the edges are not two parallel straight lines —
    a constant-width ribbon reads as a drawn road, which is the same
    hard-edged-sticker problem the plate had.
    """
    if len(points) < 2:
        return None
    verts, faces = [], []
    for i, (px, py) in enumerate(points):
        # Direction is the average of the segments either side, so corners
        # mitre instead of pinching.
        if i == 0:
            dx, dy = points[1][0] - px, points[1][1] - py
        elif i == len(points) - 1:
            dx, dy = px - points[-2][0], py - points[-2][1]
        else:
            dx = points[i + 1][0] - points[i - 1][0]
            dy = points[i + 1][1] - points[i - 1][1]
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        half = width * 0.5 * (1.0 + (_hash01(seed, i) - 0.5) * 2.0 * jitter)
        verts.append((px + nx * half, py + ny * half, z))
        verts.append((px - nx * half, py - ny * half, z))
    for i in range(len(points) - 1):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))
    obj = _mesh_from(material, name, verts, faces)
    return exclude_from_outline(obj)


def yard_plate(material, location=(0.0, 0.0, 0.0), width=1.0, depth=1.0, thickness=0.02):
    """A rectangular PAVED area — a forecourt, a parade square, a loading apron.

    Not the default ground any more. Used as one full-quad slab per building it
    is what made every asset a hard square sticker on the terrain; use
    ground_patch() for anything that is dirt, spoil or worn grass, and reach for
    this only where a straight man-made edge is the point. Keep it well inside
    the frame so it reads as a paved area within a site rather than as the
    site's own boundary.
    """
    return part(bpy.ops.mesh.primitive_cube_add, material,
                (location[0], location[1], location[2] + thickness / 2.0),
                scale=(width, depth, thickness), size=1.0)


def roof_vent(material, location, radius=0.05, height=0.06):
    """A short stack/vent/skylight read as a disc from overhead. Chimneys are the
    only rooftop detail a 90-degree camera resolves, so they carry the per-building
    rhythm that facade windows used to."""
    return part(bpy.ops.mesh.primitive_cylinder_add, material, location,
                radius=radius, depth=height)


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


def measure_content_span(category: str) -> float:
    """The ortho_scale that would exactly fit this model at `category`'s camera
    angle. Builds no image — the two-pass driver in render_category.py runs this
    over a whole category to find the one frame size that fits all of it."""
    return frame_content(add_camera(category))


def render_to(output_path: str, category: str, resolution: int = 2048,
              fit: bool = False, ortho_scale: float = None):
    """Call once at the end of an asset script, after the model + materials exist.

    fit=True sizes the frame to the model instead of add_camera()'s fixed 3.0;
    pass ortho_scale alongside it to centre on this model but frame at a size
    shared with the rest of its category (see frame_content)."""
    setup_render(resolution)
    cam_obj = add_camera(category)
    if fit:
        frame_content(cam_obj, ortho_scale)
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


# Vertical resolution of a strip render. The horizontal resolution follows
# from the requested world-space span so pixels stay square — a strip that is
# 12x as wide as it is tall comes out 12x as many pixels across.
STRIP_RESOLUTION_Y = 1024


def render_strip_to(output_path: str, category: str, span_x: float, span_y: float,
                    resolution_y: int = STRIP_RESOLUTION_Y):
    """Renders a WIDE STRIP framed to an exact world-space rectangle, for the
    wall and gate textures Line2D maps onto a segment.

    Unlike render_to(), nothing here is fitted to the model: the frame is the
    contract. `span_x` is exactly one repeat of a tileable wall (so the model
    must be periodic over that distance AND extend past both frame edges, or
    the texture will not tile), or the whole length of a one-off asset like a
    gate. `span_y` is the strip's own thickness, and it is what makes a wall
    and its gate come out the same thickness on screen: Line2D scales a
    texture's full HEIGHT onto the line's width, so any transparent margin
    above and below the wall in the image becomes wasted line width in game.

    That margin is exactly what was wrong with the first generation of this
    art. The wall models were framed by add_camera()'s fixed ortho_scale in a
    square 2048x2048 image, so the wall itself occupied ~7% of the image
    height and read in game as a thin line inside a much wider invisible band
    ("Wall assets need to look more substantial, thicker", user report) — and
    it stopped well short of the left and right edges, so it could not repeat
    ("they MUST touch the edge of the canvas on the right and left edges to
    be proper repeatable game assets").

    Straight-down only (walls/infrastructure), which is what lets `span_x`
    and `span_y` mean model X and model Y directly — see add_camera()'s own
    is_straight_down branch.
    """
    setup_render(resolution_y)
    scene = bpy.context.scene
    scene.render.resolution_y = resolution_y
    scene.render.resolution_x = int(round(resolution_y * span_x / span_y))
    # setup_render() sized the Freestyle stroke against a square frame. On a
    # strip the short axis is what the stroke has to stay proportionate to,
    # or the outline eats the asset: at 2048 wide it would be a 37px line on
    # a 512px-tall image.
    fs = bpy.context.view_layer.freestyle_settings
    fs.linesets[0].linestyle.thickness = resolution_y * OUTLINE_THICKNESS_FRACTION

    # ortho_scale sizes the LARGER image dimension, which for a strip is the
    # width — so this frames exactly span_x across, and span_y follows from
    # the pixel aspect above.
    add_camera(category, ortho_scale=span_x)
    add_flat_light()
    scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)


def render_directional_to(output_dir: str, key: str, category: str, resolution: int = 2048):
    """Renders DIRECTIONS_8 facings of the same built model to
    <output_dir>/<key>_<direction>.png, reusing one Blender session (model built
    once, only the camera moves) rather than re-invoking Blender 8 times."""
    setup_render(resolution)
    add_flat_light()
    # Straight-down categories take base yaw 0, every other category 45.
    #
    # At elevation 90 the camera looks along -Z with model +X/+Y mapped straight
    # to image X/Y (add_camera()'s is_straight_down branch), so yaw is a pure
    # in-plane rotation and the facing mapping becomes exact rather than a
    # guess: a model built facing +Y (wheel()'s documented convention) renders
    # pointing up the screen at yaw 0, which is "n". Keeping the historical 45
    # offset here would rotate every facing one notch off its own name.
    #
    # The 45 is still right for an angled category: it reproduces the framing
    # the pre-directional single-PNG art was authored at, so a unit that gains
    # facings does not visibly jump.
    # Straight-down categories take base yaw 0, every other category 45. The
    # step is POSITIVE in both cases.
    #
    # The sign here is verified, not reasoned about, because reasoning about it
    # got it wrong once: an argument that "rotating the camera by +yaw makes the
    # scene appear to rotate by -yaw, so the compass runs backwards" is
    # plausible, was acted on, and was false — it mirrored every facing except n
    # and s (which are symmetric and hide it) and had to be reverted. Eyeballing
    # a contact sheet is not enough to settle it either; that is what produced
    # the false positive.
    #
    # The test that does settle it: all eight facings are the same model under an
    # in-plane rotation, so facing i must equal the "n" image rotated CLOCKWISE
    # by 45*i on screen. Compare alpha masks and check the best-scoring rotation
    # is the one the filename claims. With this sign, all eight match.
    base_yaw = 0.0 if abs(CATEGORY_ELEVATION_DEG.get(category, 75.0) - 90.0) < 1e-6 else 45.0
    yaws = [base_yaw + i * (360.0 / len(DIRECTIONS_8)) for i in range(len(DIRECTIONS_8))]

    # ONE fit across all 8 facings, not eight independent ones.
    #
    # This is the open question tools/blender_pipeline/README.md raised against
    # ever fitting units: "render_directional.py renders 8 facings of one model,
    # so re-centring per facing would make a unit visibly wobble as it turns.
    # They need one fit computed across all 8 facings, not eight independent
    # ones." That is what this is. Every facing is framed at the largest span
    # any facing needs, so the model keeps one constant scale through a full
    # turn while still filling the frame far better than add_camera()'s fixed
    # ortho_scale=3.0 did (measured 31-62% fill across the old unit roster).
    #
    # It matters more now than it did: weapons are carried DIAGONALLY, so the
    # projected bounding box genuinely changes shape as the camera yaws, and
    # per-facing framing would scale a rifleman up and down once per rotation.
    # The frame is aimed at the ORIGIN, not re-centred on content, because the
    # origin is what the camera yaws around. frame_content() would re-centre per
    # facing, which trades the scale wobble for a translation wobble — the model
    # would visibly slide in its own quad as it turned. So: one scale, one aim
    # point, and the span is measured from the origin rather than from the
    # content's own centre.
    reach = 0.0
    for yaw_deg in yaws:
        bounds = content_bounds(add_camera(category, yaw_deg=yaw_deg))
        if bounds is None:
            continue
        min_x, max_x, min_y, max_y = bounds
        reach = max(reach, abs(min_x), abs(max_x), abs(min_y), abs(max_y))
    shared = (2.0 * reach) * (1.0 + 2.0 * CONTENT_MARGIN_FRACTION) if reach > 0.0 else None

    for direction, yaw_deg in zip(DIRECTIONS_8, yaws):
        add_camera(category, yaw_deg=yaw_deg, ortho_scale=shared)
        bpy.context.scene.render.filepath = f"{output_dir}/{key}_{direction}.png"
        bpy.ops.render.render(write_still=True)
