"""assets/props/reed.png — scattered decorative prop (wetland flavor). A
cluster of thin tall blades — distinct from every other prop by being
thin/vertical rather than a rounded mass.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

REED_COLOR = (0.5, 0.56, 0.28)
REED_DARK_COLOR = (0.38, 0.44, 0.22)
TIP_COLOR = (0.4, 0.28, 0.16)


def build():
    reed_mat = flat_material("Reed", REED_COLOR)
    reed_dark_mat = flat_material("ReedDark", REED_DARK_COLOR)
    tip_mat = flat_material("Tip", TIP_COLOR)

    # Radius 0.035 — this pipeline's established minimum (see README's
    # "Minimum part thickness"). Tilt bumped hard (was +-0.05 to 0.15 rad,
    # now 0.5 to 0.8) — props renders at a steep 75-degree bird's-eye angle
    # (see CATEGORY_ELEVATION_DEG), and near-vertical blades foreshorten to
    # almost nothing from nearly straight above, confirmed on a real render
    # (read as two small dots, not visible blades at all).
    blades = [(-0.12, 0.0, 0.42, 0.65), (0.05, 0.03, 0.5, -0.7), (0.14, -0.03, 0.44, 0.55), (-0.06, 0.06, 0.36, -0.6)]
    for i, (x, y, h, tilt) in enumerate(blades):
        mat = reed_mat if i % 2 == 0 else reed_dark_mat
        part(bpy.ops.mesh.primitive_cylinder_add, mat, (x, y, h / 2.0),
             rotation=(0, tilt, 0), scale=(1.0, 1.0, 1.0), radius=0.035, depth=h)
        part(bpy.ops.mesh.primitive_cylinder_add, tip_mat, (x + math.sin(tilt) * h * 0.5, y, h * 0.5 + math.cos(tilt) * h * 0.5),
             rotation=(0, tilt, 0), scale=(1.2, 1.2, 0.4), radius=0.025, depth=0.06)
