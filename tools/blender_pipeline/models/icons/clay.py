"""assets/icons/clay.png — GameEnums.ResourceType.CLAY. A rounded lump of
raw wet clay — no prompt existed for this one (added after the Building
tree rework).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CLAY_COLOR = (0.62, 0.35, 0.24)
CLAY_DARK_COLOR = (0.48, 0.26, 0.17)


def build():
    clay_mat = flat_material("Clay", CLAY_COLOR)
    clay_dark_mat = flat_material("ClayDark", CLAY_DARK_COLOR)

    part(bpy.ops.mesh.primitive_uv_sphere_add, clay_mat, (0, 0, 0.14), scale=(1.2, 1.1, 0.85), segments=10, ring_count=6, radius=0.24)
    part(bpy.ops.mesh.primitive_uv_sphere_add, clay_dark_mat, (0.2, -0.12, 0.06), scale=(0.7, 0.7, 0.5), segments=8, ring_count=5, radius=0.14)
