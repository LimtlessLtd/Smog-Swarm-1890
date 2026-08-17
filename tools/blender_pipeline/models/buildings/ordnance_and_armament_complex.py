"""assets/buildings/ordnance_and_armament_complex.png — GameEnums.
BuildingType.ORDNANCE_AND_ARMAMENT_COMPLEX, Tier 5 Housing & Civil. The
biggest, most fortified building on the roster — a reinforced bunker-like
hall with a mounted cannon barrel out front, escalating past
high_command_and_cavalry_depot.py's flag-and-stable civic look into a
visibly armed weapons complex.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BUNKER_COLOR = (0.448, 0.41, 0.335)
DARK_COLOR = (0.246, 0.225, 0.204)
CANNON_COLOR = (0.28, 0.27, 0.28)
CRATE_COLOR = (0.47, 0.309, 0.084)


def build():
    bunker_mat = flat_material("Bunker", BUNKER_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    cannon_mat = flat_material("Cannon", CANNON_COLOR)
    crate_mat = flat_material("Crate", CRATE_COLOR)

    # Low, wide, sloped bunker roof — no gable, reads as reinforced concrete.
    part(bpy.ops.mesh.primitive_cube_add, bunker_mat, (0, -0.05, 0.16), scale=(0.5, 0.36, 0.16), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, dark_mat, (0, -0.05, 0.28), scale=(0.44, 0.3, 0.04), size=1.0)

    # Mounted cannon barrel projecting forward from a firing slit.
    part(bpy.ops.mesh.primitive_cylinder_add, cannon_mat, (0, 0.2, 0.16),
         rotation=(1.5708, 0, 0), radius=0.045, depth=0.4)
    part(bpy.ops.mesh.primitive_cylinder_add, dark_mat, (0, 0.42, 0.16),
         rotation=(1.5708, 0, 0), scale=(1.3, 1.3, 1.0), radius=0.05, depth=0.06)

    for x, y in ((-0.3, 0.2), (-0.38, 0.12)):
        part(bpy.ops.mesh.primitive_cube_add, crate_mat, (x, y, 0.06), scale=(0.08, 0.08, 0.06), size=1.0)
