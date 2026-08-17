"""assets/buildings/clay_brickworks.png — GameEnums.BuildingType.
BRICKWORKS, Tier 1 Industry & Extraction. A kiln shed with a stack of
finished bricks out front — distinct from steam_furnace.py's rounded
kiln cone by being a rectangular shed, and from timber_camp.py's log pile
by stacking rectangular bricks instead of round logs.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

BRICK_RED_COLOR = (0.672, 0.137, 0.0)
SHED_COLOR = (0.392, 0.335, 0.297)
DARK_COLOR = (0.224, 0.188, 0.152)


def build():
    brick_mat = flat_material("Brick", BRICK_RED_COLOR)
    shed_mat = flat_material("Shed", SHED_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, shed_mat, (-0.05, -0.1, 0.2), scale=(0.4, 0.34, 0.2), size=1.0)
    chimney(dark_mat, (0.1, -0.28, 0.62), height=0.4, radius=0.06)

    # Stacked brick pallets: a grid of small red rectangular blocks — the
    # single strongest "brick" visual cue on the roster.
    for row in range(3):
        for col in range(4):
            part(bpy.ops.mesh.primitive_cube_add, brick_mat,
                 (0.2 + col * 0.09, 0.3, 0.03 + row * 0.06), scale=(0.04, 0.07, 0.03), size=1.0)
