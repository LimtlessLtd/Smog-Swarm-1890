"""assets/props/bush.png — scattered decorative prop. A low, wide,
trunk-less foliage cluster — distinct from tree.py by having no visible
stem at all, sitting directly on the ground.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BUSH_COLOR = (0.34, 0.46, 0.24)
BUSH_DARK_COLOR = (0.24, 0.36, 0.18)


def build():
    bush_mat = flat_material("Bush", BUSH_COLOR)
    bush_dark_mat = flat_material("BushDark", BUSH_DARK_COLOR)

    for x, y, r, mat in [(-0.1, 0.02, 0.18, bush_mat), (0.12, -0.03, 0.16, bush_dark_mat), (0.0, 0.12, 0.14, bush_mat)]:
        part(bpy.ops.mesh.primitive_uv_sphere_add, mat, (x, y, r * 0.7), scale=(1.1, 1.0, 0.8), segments=9, ring_count=5, radius=r)
