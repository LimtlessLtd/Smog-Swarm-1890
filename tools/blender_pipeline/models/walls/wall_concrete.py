"""assets/walls/wall_concrete.png — Tier 2 defensive wall segment.

Poured reinforced concrete seen from directly above: a heavy slab with a
raised central spine, shuttering form-lines across it at every pour joint,
and bolt heads down both sides. The sturdiest-reading of the three tiers.

Distinguished from wall_brick.py by SURFACE rather than by colour — both are
grey-topped from overhead, so the concrete carries a continuous spine with
widely spaced form-lines where the brick carries individually laid stones
with a red border. Two greys that differ only in tone merge into one shape
at map scale; two different surface patterns do not.

See models/walls/strip.py for the tiling contract the positions obey.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402
from models.walls.strip import OVERRUN, TILE_PERIOD, band_half_depth, periodic_positions  # noqa: E402

TIER = 2
HALF_DEPTH = band_half_depth(TIER)

CONCRETE_COLOR = (0.60, 0.60, 0.62)
CONCRETE_DARK_COLOR = (0.44, 0.44, 0.47)
SPINE_COLOR = (0.67, 0.67, 0.68)
BOLT_COLOR = (0.36, 0.35, 0.34)

FORM_JOINT_SPACING = TILE_PERIOD / 3.0
BOLT_SPACING = TILE_PERIOD / 6.0


def build():
    concrete_mat = flat_material("Concrete", CONCRETE_COLOR)
    concrete_dark_mat = flat_material("ConcreteDark", CONCRETE_DARK_COLOR)
    spine_mat = flat_material("Spine", SPINE_COLOR)
    bolt_mat = flat_material("Bolt", BOLT_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (0, 0, 0.25),
         scale=(OVERRUN * 2.0, HALF_DEPTH * 2.0, 0.5), size=1.0)

    # Raised spine along the crown — the silhouette cue that reads as
    # "reinforced" from straight overhead.
    part(bpy.ops.mesh.primitive_cube_add, spine_mat, (0, 0, 0.53),
         scale=(OVERRUN * 2.0, HALF_DEPTH * 0.7, 0.06), size=1.0)

    # Pour joints, cut across the full depth so they read as breaks in a
    # continuous casting rather than as decoration on top of it.
    for x in periodic_positions(FORM_JOINT_SPACING):
        part(bpy.ops.mesh.primitive_cube_add, concrete_dark_mat, (x, 0, 0.565),
             scale=(0.026, HALF_DEPTH * 2.0, 0.02), size=1.0)

    for x in periodic_positions(BOLT_SPACING, BOLT_SPACING * 0.5):
        for y in (-HALF_DEPTH * 0.82, HALF_DEPTH * 0.82):
            part(bpy.ops.mesh.primitive_cylinder_add, bolt_mat, (x, y, 0.515),
                 radius=0.026, depth=0.03, vertices=8)
