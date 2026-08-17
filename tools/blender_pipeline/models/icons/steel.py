"""assets/icons/steel.png — GameEnums.ResourceType.STEEL. Lighter,
more polished ingot bars than cast_iron.py — a brighter silver-grey
reflecting steel's refined-from-iron status.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.62, 0.63, 0.66)
STEEL_DARK_COLOR = (0.46, 0.47, 0.5)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    steel_dark_mat = flat_material("SteelDark", STEEL_DARK_COLOR)

    for i in range(3):
        mat = steel_mat if i % 2 == 0 else steel_dark_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (0, -0.1 + i * 0.1, 0.06 - i * 0.02),
             scale=(0.28, 0.08, 0.05), size=1.0)
