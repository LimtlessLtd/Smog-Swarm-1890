"""assets/icons/iron_ore.png — GameEnums.ResourceType.IRON_ORE. Rust-orange
angular rock chunks — no prompt existed for this one. Same angular-chunk
shape language as limestone.py but rust-orange, matching iron_ore_mine.py's
building ore color.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

ORE_COLOR = (0.62, 0.32, 0.16)
ORE_DARK_COLOR = (0.44, 0.22, 0.12)


def build():
    ore_mat = flat_material("Ore", ORE_COLOR)
    ore_dark_mat = flat_material("OreDark", ORE_DARK_COLOR)

    # Bigger, tightly overlapping chunks — see limestone.py's own comment
    # for why (small gapped cubes read as mostly black once outlined).
    chunks = [(-0.08, -0.03, 0.2, 0.2, ore_mat), (0.1, 0.04, 0.18, -0.15, ore_dark_mat),
              (0.0, -0.14, 0.17, 0.4, ore_mat), (-0.05, 0.15, 0.16, 0.6, ore_dark_mat)]
    for x, y, size, rot, mat in chunks:
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, size * 0.4), scale=(size, size, size), size=1.0, rotation=(0, 0, rot))
