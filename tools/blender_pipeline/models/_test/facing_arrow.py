"""Not a real game asset — a throwaway shape with an unambiguous front (a nose cone
pointing +Y) and back (a distinct-colored marker at -Y), used only to prove
render_directional_to()'s 8-facing camera sweep actually produces 8 visually
distinct, correctly-ordered renders before any real unit gets this treatment.
Delete once the directional pipeline is validated and wired into a real asset.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material  # noqa: E402

BODY_COLOR = (0.55, 0.5, 0.45)
NOSE_COLOR = (0.75, 0.15, 0.1)  # front marker — vivid red, unmissable in any facing
BACK_COLOR = (0.15, 0.35, 0.7)  # back marker — vivid blue, so front/back never ambiguous


def build():
    body_mat = flat_material("Body", BODY_COLOR)
    nose_mat = flat_material("Nose", NOSE_COLOR)
    back_mat = flat_material("Back", BACK_COLOR)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.4, depth=1.0, location=(0, 0, 0.5))
    body = bpy.context.active_object
    bpy.ops.object.shade_flat()
    body.data.materials.append(body_mat)

    bpy.ops.mesh.primitive_cone_add(radius1=0.15, depth=0.5, location=(0, 0.55, 0.6))
    nose = bpy.context.active_object
    nose.rotation_euler = (1.5708, 0, 0)  # point along +Y, cone defaults to pointing +Z
    bpy.ops.object.shade_flat()
    nose.data.materials.append(nose_mat)

    bpy.ops.mesh.primitive_cube_add(size=0.3, location=(0, -0.45, 0.7))
    back = bpy.context.active_object
    bpy.ops.object.shade_flat()
    back.data.materials.append(back_mat)
