"""assets/icons/bricks.png — GameEnums.ResourceType.BRICKS. A small stack
of red clay bricks — same subject as the old AI-prompt README.

Third pass. First two passes used a 3x3 grid of small bricks (checkerboard
two-tone) that read as mostly black at icon scale regardless of spacing
fix — each brick's own dark-shaded side faces plus its Freestyle outline
ate almost all the visible area once there were 9 of them. This pass uses
4 large bricks, one flat color (no dark alternation dragging shadow-toned
faces into dominance), matching the "few big shapes, not many small ones"
pattern that worked for wood.py/coal.py.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BRICK_COLOR = (0.7, 0.3, 0.2)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)

    for i, (x, z) in enumerate([(-0.15, 0.05), (0.05, 0.05), (-0.05, 0.14), (0.15, 0.14)]):
        part(bpy.ops.mesh.primitive_cube_add, brick_mat, (x, 0, z), scale=(0.18, 0.26, 0.08), size=1.0)
