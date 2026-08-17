"""assets/buildings/steam_furnace.png — GameEnums.BuildingType.
STEAM_FURNACE, Tier 0 Industry & Extraction. A squat brick kiln with a
glowing mouth and a single thick chimney — smaller and simpler than
iron_foundry.py's later Tier 2 furnace, establishing this as the "starter"
smelting building.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

BRICK_COLOR = (0.47, 0.15, 0.054)
DARK_COLOR = (0.246, 0.116, 0.083)
GLOW_COLOR = (0.952, 0.334, 0.0)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    glow_mat = flat_material("Glow", GLOW_COLOR)

    part(bpy.ops.mesh.primitive_cone_add, brick_mat, (0, 0, 0.24), radius1=0.32, radius2=0.24, depth=0.48)

    # Furnace mouth: a dark ring with a glowing core.
    part(bpy.ops.mesh.primitive_cylinder_add, dark_mat, (0, 0.28, 0.18),
         rotation=(1.5708, 0, 0), radius=0.13, depth=0.06)
    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (0, 0.32, 0.18),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.5), radius=0.09, depth=0.05)

    chimney(dark_mat, (0.05, -0.1, 0.66), height=0.4, radius=0.07)
