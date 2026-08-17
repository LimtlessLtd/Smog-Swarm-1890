"""assets/buildings/mechanised_farm.png — GameEnums.BuildingType.
MECHANISED_FARM, Tier 3 Agriculture. Three silos (up from
industrial_farm.py's two) plus a small mechanical harvester shape parked
on the field — a visible machine, not just crop rows, marking this as a
step up from "industrial" to "mechanised."
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, silo, wheel  # noqa: E402

FIELD_COLOR = (0.585, 0.65, 0.164)
SILO_COLOR = (0.728, 0.671, 0.556)
MACHINE_COLOR = (0.56, 0.209, 0.018)
WHEEL_COLOR = (0.168, 0.132, 0.114)


def build():
    field_mat = flat_material("Field", FIELD_COLOR)
    silo_mat = flat_material("Silo", SILO_COLOR)
    machine_mat = flat_material("Machine", MACHINE_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, field_mat, (0, 0, -0.02), scale=(1.0, 1.0, 0.04), radius=0.7, depth=0.1)

    for i in range(3):
        silo(silo_mat, (-0.35 + i * 0.16, -0.3, 0.18), radius=0.13, height=0.46)

    # Harvester: a small boxy machine with wheels, parked on the field.
    part(bpy.ops.mesh.primitive_cube_add, machine_mat, (0.25, 0.15, 0.1), scale=(0.16, 0.24, 0.09), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, machine_mat, (0.25, 0.32, 0.14), scale=(0.14, 0.06, 0.12), size=1.0)
    for x, y in ((0.15, 0.05), (0.35, 0.05), (0.15, 0.25), (0.35, 0.25)):
        wheel(wheel_mat, (x, y, 0.04), radius=0.04, thickness=0.04)

    for i in range(6):
        t = (i / 5.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, silo_mat, (-0.1, t * 0.5, 0.005), scale=(0.35, 0.015, 0.01), size=1.0)
