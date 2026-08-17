"""assets/buildings/high_command_and_cavalry_depot.png — GameEnums.
BuildingType.HIGH_COMMAND_AND_CAVALRY_DEPOT, Tier 3 Housing & Civil. A
grand hall with a flag and an attached stable — bigger and more
ornamented than garrison.py/armory_and_barracks.py, with a stable wing
(a lower attached shed with a horseshoe-arch door) marking the "cavalry"
half of the name.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WALL_COLOR = (0.55, 0.48, 0.38)
ROOF_COLOR = (0.32, 0.24, 0.18)
STABLE_COLOR = (0.42, 0.32, 0.22)
FLAG_COLOR = (0.4, 0.1, 0.5)  # Violet — the only violet building on the roster, a "command" flourish.


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    stable_mat = flat_material("Stable", STABLE_COLOR)
    flag_mat = flat_material("Flag", FLAG_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (-0.1, 0, 0.24), scale=(0.4, 0.32, 0.24), size=1.0)
    gable_roof(roof_mat, (-0.1, 0, 0.5), width=0.44, depth=0.36, height=0.22, ridge_along_y=False)

    part(bpy.ops.mesh.primitive_cube_add, stable_mat, (0.28, -0.05, 0.14), scale=(0.24, 0.34, 0.14), size=1.0)
    gable_roof(roof_mat, (0.28, -0.05, 0.26), width=0.28, depth=0.38, height=0.14, ridge_along_y=False)

    part(bpy.ops.mesh.primitive_cylinder_add, wall_mat, (-0.15, -0.05, 0.7), radius=0.02, depth=0.45)
    part(bpy.ops.mesh.primitive_cube_add, flag_mat, (-0.08, -0.05, 0.85), scale=(0.12, 0.01, 0.07), size=1.0)
