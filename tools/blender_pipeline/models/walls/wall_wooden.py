"""assets/walls/wall_wooden.png — Tier 0 defensive wall segment. A row of
sharpened wooden stakes — distinct from wall_brick.py/wall_concrete.py by
being made of individual visible posts, not one continuous slab.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WOOD_COLOR = (0.42, 0.3, 0.19)
WOOD_DARK_COLOR = (0.32, 0.22, 0.14)


def build():
    wood_mat = flat_material("Wood", WOOD_COLOR)
    wood_dark_mat = flat_material("WoodDark", WOOD_DARK_COLOR)

    for i in range(7):
        x = -0.42 + i * 0.14
        h = 0.5 if i % 2 == 0 else 0.44
        mat = wood_mat if i % 2 == 0 else wood_dark_mat
        part(bpy.ops.mesh.primitive_cylinder_add, mat, (x, 0, h / 2.0), radius=0.045, depth=h)
        part(bpy.ops.mesh.primitive_cone_add, mat, (x, 0, h + 0.04), radius1=0.045, radius2=0.005, depth=0.08)

    # Horizontal crossbar tying the posts together, low on the wall.
    part(bpy.ops.mesh.primitive_cube_add, wood_dark_mat, (0, 0.06, 0.2), scale=(0.5, 0.02, 0.03), size=1.0)
