"""assets/buildings/industrial_farm.png — GameEnums.BuildingType.
INDUSTRIAL_FARM, Tier 2 Agriculture. Twin silos and a much larger
mechanized field than estate_farm.py — no farmhouse at all (this is
industrial-scale production, not a household), the field itself dominates
the whole footprint.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, silo  # noqa: E402

FIELD_COLOR = (0.53, 0.627, 0.142)
SILO_COLOR = (0.694, 0.654, 0.554)
SILO_DARK_COLOR = (0.504, 0.464, 0.403)


def build():
    field_mat = flat_material("Field", FIELD_COLOR)
    silo_mat = flat_material("Silo", SILO_COLOR)
    silo_dark_mat = flat_material("SiloDark", SILO_DARK_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, field_mat, (0, 0, -0.02), scale=(1.0, 1.0, 0.04), radius=0.68, depth=0.1)

    # Dense mechanized crop rows — more, straighter, and closer-packed
    # than estate_farm.py's sparse 5 strips.
    for i in range(9):
        t = (i / 8.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, silo_dark_mat, (0.1, t * 0.6, 0.005), scale=(0.5, 0.015, 0.01), size=1.0)

    silo(silo_mat, (-0.3, -0.25, 0.2), radius=0.15, height=0.5)
    silo(silo_dark_mat, (-0.45, -0.1, 0.18), radius=0.13, height=0.44)
