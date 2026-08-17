"""assets/buildings/clay_pit.png — GameEnums.BuildingType.CLAY_PIT,
Tier 0 Industry & Extraction. An open excavation pit with a winch crane —
the only "hole in the ground" building on the roster, not a structure at all.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CLAY_COLOR = (0.616, 0.247, 0.086)
CLAY_DARK_COLOR = (0.448, 0.16, 0.048)
WOOD_COLOR = (0.358, 0.198, 0.053)


def build():
    clay_mat = flat_material("Clay", CLAY_COLOR)
    clay_dark_mat = flat_material("ClayDark", CLAY_DARK_COLOR)
    wood_mat = flat_material("Wood", WOOD_COLOR)

    # The pit itself: a wide shallow dark disc sunk into the ground, with a
    # smaller, lighter disc inside it (the exposed clay bed).
    part(bpy.ops.mesh.primitive_cylinder_add, clay_dark_mat, (0, 0, -0.02),
         scale=(1.0, 1.0, 0.06), radius=0.55, depth=0.1)
    part(bpy.ops.mesh.primitive_cylinder_add, clay_mat, (0, 0, 0.0),
         scale=(1.0, 1.0, 0.06), radius=0.4, depth=0.1)

    # Winch crane: a single angled post with a crossbar and a hanging bucket.
    part(bpy.ops.mesh.primitive_cylinder_add, wood_mat, (-0.25, -0.25, 0.35),
         rotation=(0.15, -0.1, 0), radius=0.045, depth=0.6)
    part(bpy.ops.mesh.primitive_cylinder_add, wood_mat, (-0.05, -0.15, 0.58),
         rotation=(1.5708, 0, 0.3), radius=0.04, depth=0.4)
    part(bpy.ops.mesh.primitive_cylinder_add, clay_dark_mat, (0.1, 0.0, 0.3),
         scale=(1.0, 1.0, 0.7), radius=0.06, depth=0.1)  # Hanging clay bucket.

    # Clay lumps piled beside the pit.
    for x, y in ((0.35, 0.3), (0.42, 0.18), (0.3, 0.42)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, clay_mat, (x, y, 0.06),
             segments=7, ring_count=4, radius=0.08)
