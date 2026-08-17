"""assets/buildings/garrison.png — GameEnums.BuildingType.GARRISON, Tier 1
Housing & Civil. A walled barracks compound — a defensive palisade wall
ring plus a flag, distinct from every civilian house/farm by reading as
fortified rather than domestic.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WALL_COLOR = (0.448, 0.379, 0.274)
ROOF_COLOR = (0.246, 0.18, 0.113)
PALISADE_COLOR = (0.336, 0.238, 0.108)
FLAG_COLOR = (0.56, 0.0, 0.0)


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    palisade_mat = flat_material("Palisade", PALISADE_COLOR)
    flag_mat = flat_material("Flag", FLAG_COLOR)

    # Palisade ring: taller, thicker, closer-spaced posts than
    # tenant_farm.py's decorative field fence — reads as fortification.
    for i in range(16):
        angle = math.tau * i / 16
        x = 0.55 * math.cos(angle)
        y = 0.55 * math.sin(angle)
        part(bpy.ops.mesh.primitive_cylinder_add, palisade_mat, (x, y, 0.14), radius=0.03, depth=0.28)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (0, 0, 0.2), scale=(0.36, 0.3, 0.2), size=1.0)
    gable_roof(roof_mat, (0, 0, 0.42), width=0.4, depth=0.34, height=0.2, ridge_along_y=False)

    # Flagpole with a small flag.
    part(bpy.ops.mesh.primitive_cylinder_add, palisade_mat, (0, -0.1, 0.62), radius=0.015, depth=0.4)
    part(bpy.ops.mesh.primitive_cube_add, flag_mat, (0.06, -0.1, 0.75), scale=(0.1, 0.01, 0.06), size=1.0)
