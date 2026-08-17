"""assets/infrastructure/road.png — Road supply line (design_doc.md §3's
Dirt/Cobblestone/Concrete tiers; BuildMenuView shows one icon per
SupplyLineType, not per tier, so this renders the Cobblestone look — the
middle tier, most visually distinct from bare dirt or a flat concrete
slab). Built along local X (the segment's LENGTH axis) as a short strip,
same convention wall_*.py already established, so it tiles the same way
via WallVisuals.apply_line_geometry()'s LINE_TEXTURE_TILE math.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

DIRT_COLOR = (0.38, 0.28, 0.18)
SETT_COLOR = (0.55, 0.53, 0.5)
SETT_DARK_COLOR = (0.44, 0.42, 0.4)


def build():
    dirt_mat = flat_material("Dirt", DIRT_COLOR)
    sett_mat = flat_material("Sett", SETT_COLOR)
    sett_dark_mat = flat_material("SettDark", SETT_DARK_COLOR)

    # Base bed the setts sit in — visible as mortar/dirt lines between stones.
    part(bpy.ops.mesh.primitive_cube_add, dirt_mat, (0, 0, 0.02), scale=(1.0, 0.42, 0.04), size=1.0)

    # Cobblestone setts: a brick-course offset grid of rounded cubes, same
    # "offset alternate rows" pattern wall_brick.py uses for its brick
    # courses — reads as individual stones from directly above.
    for row in range(3):
        y = -0.13 + row * 0.13
        offset = 0.055 if row % 2 else 0.0
        for col in range(8):
            x = -0.46 + col * 0.13 + offset
            mat = sett_dark_mat if (row + col) % 2 else sett_mat
            part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, 0.05), scale=(0.055, 0.055, 0.045), size=1.0)
