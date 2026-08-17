"""assets/buildings/mechanized_maintenance_depot.png — GameEnums.
BuildingType.MECHANIZED_MAINTENANCE_DEPOT, Tier 4 Industry & Extraction.
An open-fronted repair shed with a vehicle wheel/axle assembly visible
inside — the only building showing a "vehicle under repair," reading as
a garage rather than a production site.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

SHED_COLOR = (0.36, 0.34, 0.32)
ROOF_COLOR = (0.22, 0.2, 0.19)
CHASSIS_COLOR = (0.45, 0.25, 0.16)
WHEEL_COLOR = (0.14, 0.13, 0.12)


def build():
    shed_mat = flat_material("Shed", SHED_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    chassis_mat = flat_material("Chassis", CHASSIS_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)

    for x in (-0.28, 0.28):
        part(bpy.ops.mesh.primitive_cylinder_add, shed_mat, (x, -0.15, 0.18), radius=0.03, depth=0.36)
    part(bpy.ops.mesh.primitive_cube_add, roof_mat, (0, -0.15, 0.4), scale=(0.65, 0.4, 0.06), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, chassis_mat, (0, 0.1, 0.14), scale=(0.3, 0.4, 0.06), size=1.0)
    for x, y in ((-0.14, -0.1), (0.14, -0.1), (-0.14, 0.3), (0.14, 0.3)):
        wheel(wheel_mat, (x, y, 0.06), radius=0.06, thickness=0.05)
