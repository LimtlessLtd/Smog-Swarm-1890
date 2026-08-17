"""assets/icons/cast_iron.png — GameEnums.ResourceType.IRON. Filename
stays "cast_iron" — ResourceVisuals._icon_key() maps IRON there
deliberately (see that function's own comment). Dark grey ingot bars —
distinct from steel.py's lighter, more polished ingots by being duller
and rougher-toned.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

IRON_COLOR = (0.3, 0.3, 0.32)
IRON_DARK_COLOR = (0.2, 0.2, 0.22)


def build():
    iron_mat = flat_material("Iron", IRON_COLOR)
    iron_dark_mat = flat_material("IronDark", IRON_DARK_COLOR)

    for i in range(3):
        mat = iron_mat if i % 2 == 0 else iron_dark_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (0, -0.1 + i * 0.1, 0.06 - i * 0.02),
             scale=(0.28, 0.08, 0.05), size=1.0)
