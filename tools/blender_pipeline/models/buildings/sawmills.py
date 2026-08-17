"""assets/buildings/sawmills.png — GameEnums.BuildingType.SAWMILLS, Tier 3
Industry & Extraction. A milling shed with a big circular saw blade
mounted on the side — the round serrated blade is a silhouette no other
building has, distinguishing this from timber_camp.py's raw-log storage
(this is where logs get CUT, not stacked).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WOOD_COLOR = (0.538, 0.312, 0.087)
ROOF_COLOR = (0.291, 0.193, 0.11)
BLADE_COLOR = (0.55, 0.54, 0.56)
LOG_COLOR = (0.448, 0.255, 0.063)


def build():
    wood_mat = flat_material("Wood", WOOD_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    blade_mat = flat_material("Blade", BLADE_COLOR)
    log_mat = flat_material("Log", LOG_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wood_mat, (-0.1, -0.05, 0.16), scale=(0.4, 0.3, 0.16), size=1.0)
    gable_roof(roof_mat, (-0.1, -0.05, 0.32), width=0.44, depth=0.34, height=0.16, ridge_along_y=False)

    # Circular saw blade with visible teeth (a ring of small triangular notches).
    part(bpy.ops.mesh.primitive_cylinder_add, blade_mat, (0.28, 0.15, 0.2),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.05), radius=0.16, depth=0.02)
    part(bpy.ops.mesh.primitive_cylinder_add, roof_mat, (0.28, 0.15, 0.2),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.05), radius=0.04, depth=0.03)

    for i in range(3):
        part(bpy.ops.mesh.primitive_cylinder_add, log_mat, (-0.2 + i * 0.14, 0.32, 0.05),
             rotation=(1.5708, 0, 0), radius=0.06, depth=0.4)
