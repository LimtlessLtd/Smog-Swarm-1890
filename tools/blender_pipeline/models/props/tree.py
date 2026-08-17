"""assets/props/tree.png — scattered decorative prop. Trunk + a rounded
canopy — the tallest of the 4 props, with a visible bare trunk
distinguishing it from bush.py's ground-hugging foliage-only shape.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

TRUNK_COLOR = (0.36, 0.24, 0.15)
CANOPY_COLOR = (0.28, 0.42, 0.2)
CANOPY_DARK_COLOR = (0.2, 0.32, 0.15)


def build():
    trunk_mat = flat_material("Trunk", TRUNK_COLOR)
    canopy_mat = flat_material("Canopy", CANOPY_COLOR)
    canopy_dark_mat = flat_material("CanopyDark", CANOPY_DARK_COLOR)

    part(bpy.ops.mesh.primitive_cone_add, trunk_mat, (0, 0, 0.18), radius1=0.05, radius2=0.035, depth=0.36)

    part(bpy.ops.mesh.primitive_uv_sphere_add, canopy_mat, (0, 0, 0.5), scale=(1.0, 1.0, 0.9), segments=10, ring_count=6, radius=0.26)
    part(bpy.ops.mesh.primitive_uv_sphere_add, canopy_dark_mat, (0.12, 0.1, 0.42), scale=(0.7, 0.7, 0.6), segments=8, ring_count=5, radius=0.18)
