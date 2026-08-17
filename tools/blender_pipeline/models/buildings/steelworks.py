"""assets/buildings/steelworks.png — GameEnums.BuildingType.STEELWORKS,
Tier 3 Industry & Extraction. A bigger, taller escalation of
iron_foundry.py — twin stacks instead of one, and a bright white-hot glow
(hotter than iron_foundry's orange) reflecting steel's higher furnace
temperature.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

STEEL_WALL_COLOR = (0.4, 0.4, 0.44)
DARK_COLOR = (0.24, 0.23, 0.24)
GLOW_COLOR = (0.95, 0.9, 0.6)


def build():
    wall_mat = flat_material("Wall", STEEL_WALL_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    glow_mat = flat_material("Glow", GLOW_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (0, -0.05, 0.22), scale=(0.5, 0.36, 0.22), size=1.0)

    chimney(dark_mat, (-0.16, -0.05, 0.76), height=0.6, radius=0.08)
    chimney(dark_mat, (0.16, -0.05, 0.76), height=0.6, radius=0.08)

    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (0, 0.28, 0.14),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.4), radius=0.12, depth=0.05)
