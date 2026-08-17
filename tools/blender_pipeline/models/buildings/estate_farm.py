"""assets/buildings/estate_farm.png — GameEnums.BuildingType.ESTATE_FARM,
Tier 1 Agriculture. A bigger, grander version of tenant_farm.py — a real
farmhouse (not a single small hut) plus a silo, reflecting the tier-up
from "smallholding" to "estate."
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof, silo, fence_perimeter  # noqa: E402

FIELD_COLOR = (0.46, 0.54, 0.24)
WALL_COLOR = (0.72, 0.65, 0.5)
ROOF_COLOR = (0.42, 0.2, 0.15)
SILO_COLOR = (0.55, 0.53, 0.48)
FENCE_COLOR = (0.35, 0.24, 0.14)


def build():
    field_mat = flat_material("Field", FIELD_COLOR)
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    silo_mat = flat_material("Silo", SILO_COLOR)
    fence_mat = flat_material("Fence", FENCE_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, field_mat, (0, 0, -0.02), scale=(1.0, 1.0, 0.04), radius=0.65, depth=0.1)
    fence_perimeter(fence_mat, count=14, distance=0.6, post_height=0.1, post_radius=0.02)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (-0.2, -0.05, 0.22), scale=(0.4, 0.3, 0.22), size=1.0)
    gable_roof(roof_mat, (-0.2, -0.05, 0.44), width=0.44, depth=0.34, height=0.2, ridge_along_y=False)

    silo(silo_mat, (0.15, -0.15, 0.15), radius=0.13, height=0.4)

    for i in range(5):
        t = (i / 4.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, wall_mat, (0.2, t * 0.55, 0.005), scale=(0.4, 0.02, 0.01), size=1.0)
