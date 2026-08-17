"""assets/buildings/workhouse.png — GameEnums.BuildingType.BRICK_HOUSES,
Tier 1 Housing & Civil. A single larger brick building (not a row of 3
like terraced_tenement.py) with a taller, steeper roof and real red brick
color — a tier-up housing silhouette, bigger and more solid than Tier 0's
wooden terrace.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

BRICK_COLOR = (0.58, 0.3, 0.22)
ROOF_COLOR = (0.24, 0.2, 0.18)
WINDOW_COLOR = (0.55, 0.6, 0.62)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    window_mat = flat_material("Window", WINDOW_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, brick_mat, (0, 0, 0.24), scale=(0.44, 0.34, 0.24), size=1.0)
    gable_roof(roof_mat, (0, 0, 0.5), width=0.48, depth=0.38, height=0.24, ridge_along_y=False)

    for x in (-0.12, 0.12):
        part(bpy.ops.mesh.primitive_cube_add, window_mat, (x, 0.18, 0.24), scale=(0.06, 0.01, 0.06), size=1.0)
