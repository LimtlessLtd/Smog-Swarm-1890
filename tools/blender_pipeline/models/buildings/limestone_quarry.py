"""assets/buildings/limestone_quarry.png — GameEnums.BuildingType.LIMESTONE_QUARRY.

Against clay_pit's round stepped hole, a quarry is a STRAIGHT worked face: benches
cut square along one side of the site, in stone pale enough to be the brightest
ground on the whole building roster. Rock face plus a kiln pair; no shaft, no
headframe.

Re-authored 2026-09-15 for the straight-down camera, on the extraction family's
ground/path system (see coal_pithead.py for the reference model, and
render_common's organic-ground block for why the old full-quad plate went).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, ground_patch, path, family_materials,
)

ORE_COLOR = (0.800, 0.780, 0.714)  # cut limestone


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    stone_mat = flat_material("Stone", ORE_COLOR)
    dust_mat = flat_material("Dust", (0.702, 0.682, 0.620), alpha=0.86)
    track_mat = flat_material("Track", (0.600, 0.580, 0.522), alpha=0.92)

    ground_patch(dust_mat, (0.0, 0.0, 0.002), radius_x=0.58, radius_y=0.50,
                 sides=15, jitter=0.20, seed=501, name="QuarryFloor")

    # Worked face: four straight benches stepping back, square-cut. The hard
    # parallel edges are the opposite of clay_pit's concentric rings.
    for i in range(4):
        shade = 1.0 - i * 0.13
        bench_mat = flat_material("Bench%d" % i, tuple(c * shade for c in ORE_COLOR))
        part(bpy.ops.mesh.primitive_cube_add, bench_mat,
             (-0.34 + i * 0.03, 0.30 - i * 0.075, 0.030 + i * 0.022),
             scale=(0.74 - i * 0.06, 0.13, 0.045 + i * 0.030), size=1.0)

    # Haul road from the face out past the kilns.
    path(track_mat, [(-0.30, 0.06), (-0.06, -0.10), (0.24, -0.24), (0.48, -0.28)],
         width=0.12, seed=509)

    # Lime kilns: a PAIR of squat cylinders with dark mouths. Nothing else in the
    # family has matched round openings at ground level.
    for x in (0.26, 0.50):
        part(bpy.ops.mesh.primitive_cylinder_add, stone_mat, (x, 0.18, 0.13),
             radius=0.145, depth=0.26)
        part(bpy.ops.mesh.primitive_cylinder_add, shaft_mat, (x, 0.18, 0.265),
             radius=0.062, depth=0.03)

    # Dressed block stock, stacked square on the floor.
    for ix in range(3):
        for iy in range(2):
            part(bpy.ops.mesh.primitive_cube_add, stone_mat,
                 (-0.30 + ix * 0.085, -0.38 + iy * 0.080, 0.040),
                 scale=(0.066, 0.062, 0.042), size=1.0)
