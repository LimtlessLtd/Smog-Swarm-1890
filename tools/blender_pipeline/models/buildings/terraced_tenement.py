"""assets/buildings/terraced_tenement.png — GameEnums.BuildingType.
WOODEN_HOUSES, Tier 0 Housing & Civil. A row of 3 connected narrow houses
— the repeated-unit silhouette (multiple gables in a line) is unique to
housing buildings, distinguishing this category from single-structure
Industry/Agriculture buildings at a glance.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WALL_COLORS = [(0.62, 0.5, 0.36), (0.55, 0.42, 0.3), (0.6, 0.46, 0.34)]  # Slightly varied per house — a real terrace isn't one uniform color.
ROOF_COLOR = (0.28, 0.22, 0.18)
DOOR_COLOR = (0.3, 0.18, 0.1)


def build():
    roof_mat = flat_material("Roof", ROOF_COLOR)
    door_mat = flat_material("Door", DOOR_COLOR)

    for i, wall_color in enumerate(WALL_COLORS):
        wall_mat = flat_material("Wall%d" % i, wall_color)
        x = (i - 1) * 0.34
        part(bpy.ops.mesh.primitive_cube_add, wall_mat, (x, 0, 0.18), scale=(0.3, 0.26, 0.18), size=1.0)
        gable_roof(roof_mat, (x, 0, 0.35), width=0.34, depth=0.3, height=0.16, ridge_along_y=False)
        part(bpy.ops.mesh.primitive_cube_add, door_mat, (x, 0.14, 0.08), scale=(0.06, 0.02, 0.08), size=1.0)
