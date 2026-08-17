"""assets/icons/limestone.png — GameEnums.ResourceType.LIMESTONE. Pale
angular stone chunks — no prompt existed for this one (added after the
Building tree rework). Angular (cubes), not rounded (spheres), and pale
grey-white — the clearest visual distinction from clay.py/coal.py's
rounded, dark-toned lumps.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STONE_COLOR = (0.8, 0.78, 0.72)
STONE_DARK_COLOR = (0.6, 0.58, 0.53)


def build():
    stone_mat = flat_material("Stone", STONE_COLOR)
    stone_dark_mat = flat_material("StoneDark", STONE_DARK_COLOR)

    # Bigger, tightly overlapping chunks — a first pass with small (0.12-0.16)
    # gapped cubes read as mostly black once the Freestyle outline wrapped
    # each one individually (confirmed on a real render): overlap kills the
    # gaps, same fix coal.py's icosphere cluster already relied on successfully.
    chunks = [(-0.08, -0.03, 0.2, 0.2, stone_mat), (0.1, 0.04, 0.18, -0.15, stone_dark_mat),
              (0.0, -0.14, 0.17, 0.4, stone_mat), (-0.05, 0.15, 0.16, 0.6, stone_dark_mat)]
    for x, y, size, rot, mat in chunks:
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, size * 0.4), scale=(size, size, size), size=1.0, rotation=(0, 0, rot))
