"""assets/buildings/town_hall.png — GameEnums.BuildingType.TOWN_HALL, Tier
3 Housing & Civil. The colony's founding/prestige building — a grand hall
with a clock tower, the tallest and most ornamented civic structure on the
roster (taller than high_command_and_cavalry_depot.py, and the only
building with a clock face), reflecting its unique founding-structure status.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WALL_COLOR = (0.672, 0.538, 0.336)
ROOF_COLOR = (0.336, 0.235, 0.168)
TOWER_COLOR = (0.56, 0.459, 0.29)
CLOCK_COLOR = (0.952, 0.862, 0.647)
CLOCK_HAND_COLOR = (0.168, 0.134, 0.084)


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    tower_mat = flat_material("Tower", TOWER_COLOR)
    clock_mat = flat_material("Clock", CLOCK_COLOR)
    hand_mat = flat_material("ClockHand", CLOCK_HAND_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (-0.05, 0, 0.24), scale=(0.5, 0.36, 0.24), size=1.0)
    gable_roof(roof_mat, (-0.05, 0, 0.5), width=0.54, depth=0.4, height=0.24, ridge_along_y=False)

    # Clock tower — taller than the main hall, rising well above the roofline.
    part(bpy.ops.mesh.primitive_cylinder_add, tower_mat, (0.28, 0, 0.5), scale=(1.0, 1.0, 1.0), radius=0.14, depth=0.6)
    part(bpy.ops.mesh.primitive_cylinder_add, clock_mat, (0.28, 0.13, 0.72), rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.3), radius=0.1, depth=0.05)
    part(bpy.ops.mesh.primitive_cube_add, hand_mat, (0.28, 0.16, 0.72), scale=(0.01, 0.01, 0.06), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, hand_mat, (0.28, 0.16, 0.75), scale=(0.05, 0.01, 0.01), size=1.0)
    part(bpy.ops.mesh.primitive_cone_add, roof_mat, (0.28, 0, 0.92), radius1=0.16, radius2=0.02, depth=0.24)
