"""assets/icons/sulfur.png — GameEnums.ResourceType.SULFUR. Vivid yellow
angular chunks — no prompt existed for this one. Bright yellow is unique
across the whole icon set, matching sulfur_mine.py's building ore color.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

SULFUR_COLOR = (0.88, 0.8, 0.18)
SULFUR_DARK_COLOR = (0.68, 0.6, 0.1)


def build():
    sulfur_mat = flat_material("Sulfur", SULFUR_COLOR)
    sulfur_dark_mat = flat_material("SulfurDark", SULFUR_DARK_COLOR)

    # Bigger, tightly overlapping chunks — see limestone.py's own comment
    # for why (small gapped cubes read as mostly black once outlined).
    chunks = [(-0.08, -0.03, 0.2, 0.2, sulfur_mat), (0.1, 0.04, 0.18, -0.15, sulfur_dark_mat),
              (0.0, -0.14, 0.17, 0.4, sulfur_mat), (-0.05, 0.15, 0.16, 0.6, sulfur_dark_mat)]
    for x, y, size, rot, mat in chunks:
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, size * 0.4), scale=(size, size, size), size=1.0, rotation=(0, 0, rot))
