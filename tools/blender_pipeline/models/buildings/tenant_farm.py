"""assets/buildings/tenant_farm.png — GameEnums.BuildingType.
SMALLHOLDING_FARM, Tier 0 Agriculture. A small farmhouse with a fenced
field — the field patch (a wide flat green plane) is unique to farm
buildings, distinguishing this whole category from Industry/Housing at a glance.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof, fence_perimeter  # noqa: E402

FIELD_COLOR = (0.42, 0.5, 0.22)
WALL_COLOR = (0.68, 0.6, 0.48)
ROOF_COLOR = (0.5, 0.22, 0.16)
FENCE_COLOR = (0.35, 0.24, 0.14)


def build():
    field_mat = flat_material("Field", FIELD_COLOR)
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    fence_mat = flat_material("Fence", FENCE_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, field_mat, (0, 0, -0.02),
         scale=(1.0, 1.0, 0.04), radius=0.6, depth=0.1)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (-0.15, -0.05, 0.18), scale=(0.28, 0.24, 0.18), size=1.0)
    gable_roof(roof_mat, (-0.15, -0.05, 0.36), width=0.32, depth=0.28, height=0.16, ridge_along_y=False)

    fence_perimeter(fence_mat, count=12, distance=0.55, post_height=0.1, post_radius=0.015)

    # Crop rows: a few thin parallel strips across the field.
    for i in range(4):
        t = (i / 3.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, wall_mat, (0.15, t * 0.5, 0.005),
             scale=(0.35, 0.02, 0.01), size=1.0)
