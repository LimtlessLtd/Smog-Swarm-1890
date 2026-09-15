"""assets/buildings/garrison.png — GameEnums.BuildingType.GARRISON.

Re-authored 2026-09-15 for the straight-down camera, and the military family's
reference model. Overhead the old model was a small brown box inside a wide ring
of fence posts: the posts occupied most of the frame, so the building itself
rendered at a fraction of its quad (measured 23.6% fill at the low end of the
category).

The military signature is a parade square with barrack blocks ranged along two
sides and a red flag disc at the head of it — a garrison from the air is a
courtyard, not a shed. Military keeps a straight-edged parade square for the same
reason civic keeps a paved forecourt (a drill square really is laid out square),
but it sits on irregular trodden ground with paths worn between the blocks rather
than on a full-quad slab.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, yard_plate, roof_vent, ground_patch, path,
    family_materials,
)

GUARD_XY = (-0.42, -0.04)


def build():
    olive_mat, roof_mat, flag_mat = family_materials("military")
    parade_mat = flat_material("Parade", (0.545, 0.522, 0.416))
    ground_mat = flat_material("Trodden", (0.388, 0.380, 0.294), alpha=0.80)
    track_mat = flat_material("Track", (0.573, 0.553, 0.447), alpha=0.92)

    ground_patch(ground_mat, (0.0, -0.02, 0.002), radius_x=0.56, radius_y=0.50,
                 sides=15, jitter=0.20, seed=71, name="Compound")
    for side, seed in ((-1.0, 73), (1.0, 79)):
        ground_patch(ground_mat, (0.0, side * 0.40, 0.002), radius_x=0.44,
                     radius_y=0.16, sides=12, jitter=0.28, seed=seed,
                     name="BarrackGround%d" % int(side))

    # Worn routes: guardhouse along the square, and out to each barrack block.
    path(track_mat, [(GUARD_XY[0] + 0.14, GUARD_XY[1]), (0.0, -0.04), (0.42, -0.06)],
         width=0.10, seed=83)
    for side in (-1.0, 1.0):
        path(track_mat, [(-0.10, -0.04), (-0.12, side * 0.20), (-0.14, side * 0.32)],
             width=0.08, seed=89 + int(side) * 3)

    # Parade square: paler, and deliberately rectangular.
    yard_plate(parade_mat, location=(0.06, -0.04, 0.004), width=0.56, depth=0.42,
               thickness=0.012)

    # Two barrack blocks ranged along the long sides of the square, each a
    # hipped roof with a row of three chimneys.
    for side in (-1.0, 1.0):
        y = side * 0.36
        part(bpy.ops.mesh.primitive_cube_add, olive_mat, (0.0, y, 0.08),
             scale=(0.72, 0.22, 0.14), size=1.0)
        hip_roof(roof_mat, (0.0, y, 0.15), width=0.68, depth=0.20,
                 height=0.13, ridge_fraction=0.76, name="Barrack%d" % int(side))
        for x in (-0.22, 0.0, 0.22):
            roof_vent(olive_mat, (x, y, 0.25), radius=0.028, height=0.08)

    # Guardhouse at the head of the square, with the flagstaff. The flag disc is
    # the only saturated red in the family palette and marks military buildings
    # the way the gold finial marks civic ones.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (GUARD_XY[0], GUARD_XY[1], 0.10),
         scale=(0.20, 0.28, 0.18), size=1.0)
    hip_roof(roof_mat, (GUARD_XY[0], GUARD_XY[1], 0.19), width=0.18, depth=0.26,
             height=0.14, ridge_fraction=0.0, name="GuardCap")
    part(bpy.ops.mesh.primitive_cylinder_add, flag_mat, (GUARD_XY[0], GUARD_XY[1], 0.36),
         radius=0.055, depth=0.04)

    # Arms racks on the square: short paired bars, the clutter that reads as
    # "drilling ground" rather than "empty yard".
    for i in range(3):
        part(bpy.ops.mesh.primitive_cube_add, roof_mat,
             (0.12 + i * 0.12, -0.04, 0.022), scale=(0.020, 0.15, 0.022), size=1.0)
