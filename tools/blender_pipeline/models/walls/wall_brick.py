"""assets/walls/wall_brick.png — Tier 1 defensive wall segment. A
continuous red brick wall with a coping ledge on top — one solid slab
with a visible brick course pattern, distinct from wall_wooden.py's
individual posts.

Top-down (walls' current camera angle): the coping ledge is the topmost
surface across the segment's full width, fully occluding the brick
coursing below it — a flat coping alone rendered as a plain rectangle,
indistinguishable in silhouette from wall_concrete.py's slab. The seam
strips below give the coping itself a visible "individual coping stones"
seam pattern so it still reads as brick from directly above, not just by
color.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BRICK_COLOR = (0.58, 0.26, 0.18)
BRICK_DARK_COLOR = (0.48, 0.2, 0.14)
COPING_COLOR = (0.42, 0.4, 0.36)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    brick_dark_mat = flat_material("BrickDark", BRICK_DARK_COLOR)
    coping_mat = flat_material("Coping", COPING_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, brick_mat, (0, 0, 0.24), scale=(1.0, 0.08, 0.48), size=1.0)

    for row in range(4):
        z = 0.05 + row * 0.12
        offset = 0.06 if row % 2 else 0.0
        for col in range(4):
            mat = brick_dark_mat if (row + col) % 2 else brick_mat
            part(bpy.ops.mesh.primitive_cube_add, mat, (-0.42 + col * 0.28 + offset, 0.041, z),
                 scale=(0.13, 0.005, 0.05), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, coping_mat, (0, 0, 0.5), scale=(1.02, 0.1, 0.03), size=1.0)

    # Coping-stone seams, visible from directly above (see module doc comment).
    coping_dark_mat = flat_material("CopingDark", tuple(c * 0.75 for c in COPING_COLOR))
    for i in range(7):
        x = -0.45 + i * 0.15
        part(bpy.ops.mesh.primitive_cube_add, coping_dark_mat, (x, 0, 0.516), scale=(0.012, 0.1, 0.002), size=1.0)
