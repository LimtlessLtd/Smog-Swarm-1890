"""assets/buildings/coal_powerplant.png — GameEnums.BuildingType.
COAL_POWERPLANT, Tier 1 Industry & Extraction. Twin tall chimneys on a
long low hall — the paired-chimney silhouette is unique to power
generation buildings, distinguishing it from single-chimney furnaces/kilns.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

HALL_COLOR = (0.3, 0.28, 0.28)
DARK_COLOR = (0.16, 0.15, 0.15)
COAL_COLOR = (0.08, 0.08, 0.08)


def build():
    hall_mat = flat_material("Hall", HALL_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    coal_mat = flat_material("Coal", COAL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, hall_mat, (0, -0.1, 0.16), scale=(0.55, 0.32, 0.16), size=1.0)

    chimney(dark_mat, (-0.2, -0.1, 0.62), height=0.5, radius=0.065)
    chimney(dark_mat, (0.2, -0.1, 0.62), height=0.5, radius=0.065)

    part(bpy.ops.mesh.primitive_cylinder_add, coal_mat, (0, 0.25, 0.05), scale=(1.0, 1.0, 0.5), radius=0.14, depth=0.1)
