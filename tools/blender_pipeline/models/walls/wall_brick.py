"""assets/walls/wall_brick.png — Tier 1 defensive wall segment.

A coursed red-brick rampart with a stone coping along the top, seen from
directly above. Solid where wall_wooden.py is made of posts.

Top-down, the coping is the only surface a straight-down camera can see —
the brick coursing below it is fully occluded, so a plain coping renders as
a featureless rectangle indistinguishable from wall_concrete.py's slab. The
coping is therefore built as individual STONES with real gaps between them,
and the brick face is only visible in the strip of it that overhangs the
coping on both long edges. That overhang is deliberate, not sloppy framing:
it is what identifies this as brick from the only angle the game ever shows.

See models/walls/strip.py for the tiling contract the positions obey.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402
from models.walls.strip import OVERRUN, TILE_PERIOD, band_half_depth, periodic_positions  # noqa: E402

TIER = 1
HALF_DEPTH = band_half_depth(TIER)

BRICK_COLOR = (0.58, 0.26, 0.18)
BRICK_DARK_COLOR = (0.46, 0.19, 0.13)
COPING_COLOR = (0.46, 0.44, 0.40)
COPING_DARK_COLOR = (0.34, 0.33, 0.30)

COPING_STONE_LENGTH = TILE_PERIOD / 5.0
COPING_HALF_DEPTH = HALF_DEPTH * 0.7  # Narrower than the brick below it, so the brick shows as a border on both sides.
BORDER_HALF_DEPTH = (HALF_DEPTH - COPING_HALF_DEPTH) / 2.0  ## Half-width of the brick strip left uncovered on each side of the coping.


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    brick_dark_mat = flat_material("BrickDark", BRICK_DARK_COLOR)
    coping_mat = flat_material("Coping", COPING_COLOR)
    coping_dark_mat = flat_material("CopingDark", COPING_DARK_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, brick_mat, (0, 0, 0.21),
         scale=(OVERRUN * 2.0, HALF_DEPTH * 2.0, 0.42), size=1.0)

    # Coursing along the two strips of brick the coping does not cover.
    #
    # Laid ON the top surface, not on the wall's vertical face: a straight-
    # down camera cannot see a vertical face at all, so the first pass at
    # this put four courses down the side of the slab and rendered a flat red
    # border with no brick in it. What reads as brick from overhead is the
    # bond pattern of the top course, staggered half a brick between the two
    # sides.
    course_length = COPING_STONE_LENGTH / 2.0
    border_y = HALF_DEPTH - BORDER_HALF_DEPTH
    for side, y in ((0, -border_y), (1, border_y)):
        phase = 0.0 if side == 0 else course_length * 0.5
        for i, x in enumerate(periodic_positions(course_length, phase)):
            mat = brick_dark_mat if i % 2 == 0 else brick_mat
            part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, 0.425),
                 scale=(course_length * 0.86, BORDER_HALF_DEPTH * 1.8, 0.02), size=1.0)

    # Coping stones, laid individually with a mortar gap between each.
    for i, x in enumerate(periodic_positions(COPING_STONE_LENGTH)):
        mat = coping_mat if i % 2 == 0 else coping_dark_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, 0, 0.47),
             scale=(COPING_STONE_LENGTH * 0.9, COPING_HALF_DEPTH * 2.0, 0.1), size=1.0)
