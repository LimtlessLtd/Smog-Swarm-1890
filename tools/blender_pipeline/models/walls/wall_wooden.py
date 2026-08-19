"""assets/walls/wall_wooden.png — Tier 0 defensive wall segment.

A timber palisade seen from directly above: two lines of driven stakes along
the outer edges of an earth rampart, with a boarded wall-walk between them.
Distinct from wall_brick.py/wall_concrete.py by being visibly made of
individual posts and planks rather than one continuous slab.

The post rows sit on the EDGES rather than down the middle because from
straight overhead the edges are the whole silhouette — a palisade read from
above is two rows of round post-tops with something between them, and moving
the posts inboard just makes an ambiguous textured band.

Built as a TILEABLE STRIP (render_common.render_strip_to). Two rules the
geometry has to obey, neither visible in a single render:

  1. Every feature repeats on a period that divides TILE_PERIOD exactly and
     is placed at a multiple of that period measured from the origin, so the
     frame's left and right edges cut identical geometry.
  2. The wall runs to +/-OVERRUN, well past the frame, so it is CUT by the
     frame edges rather than ending short of them.

tools/blender_pipeline/verify_strips.py checks both against the rendered
pixels rather than trusting this comment.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402
from models.walls.strip import OVERRUN, TILE_PERIOD, band_half_depth, periodic_positions  # noqa: E402

TIER = 0
HALF_DEPTH = band_half_depth(TIER)

WOOD_COLOR = (0.46, 0.33, 0.20)
WOOD_DARK_COLOR = (0.33, 0.23, 0.14)
EARTH_COLOR = (0.30, 0.25, 0.19)

POST_SPACING = TILE_PERIOD / 10.0
POST_RADIUS = 0.038
POST_HEIGHT = 0.5
PLANK_SPACING = TILE_PERIOD / 10.0


def build():
    wood_mat = flat_material("Wood", WOOD_COLOR)
    wood_dark_mat = flat_material("WoodDark", WOOD_DARK_COLOR)
    earth_mat = flat_material("Earth", EARTH_COLOR)

    # Rampart: fills the strip's full depth so the wall reads as solid
    # between the posts rather than as a transparent gap.
    part(bpy.ops.mesh.primitive_cube_add, earth_mat, (0, 0, 0.05),
         scale=(OVERRUN * 2.0, HALF_DEPTH * 2.0, 0.1), size=1.0)

    # Wall-walk: boards laid ACROSS the wall between the two post rows.
    walk_half_depth = HALF_DEPTH - POST_RADIUS * 2.2
    for i, x in enumerate(periodic_positions(PLANK_SPACING, PLANK_SPACING * 0.5)):
        mat = wood_mat if i % 2 == 0 else wood_dark_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, 0, 0.16),
             scale=(PLANK_SPACING * 0.78, walk_half_depth * 2.0, 0.12), size=1.0)

    for row, y in ((0, -(HALF_DEPTH - POST_RADIUS)), (1, HALF_DEPTH - POST_RADIUS)):
        for i, x in enumerate(periodic_positions(POST_SPACING, 0.0 if row == 0 else POST_SPACING * 0.5)):
            mat = wood_mat if (i + row) % 2 == 0 else wood_dark_mat
            part(bpy.ops.mesh.primitive_cylinder_add, mat, (x, y, POST_HEIGHT / 2.0),
                 radius=POST_RADIUS, depth=POST_HEIGHT, vertices=10)
            # Sharpened tip — what turns each post from a flat disc into
            # something with a readable point from directly overhead.
            part(bpy.ops.mesh.primitive_cone_add, mat, (x, y, POST_HEIGHT + 0.05),
                 radius1=POST_RADIUS, radius2=0.005, depth=0.1, vertices=10)
