"""assets/buildings/sawmills.png — GameEnums.BuildingType.SAWMILLS.

Tier 3 Wood consolidator — timber_camp's log ends kept as the family mark, but
now fed through a real mill: a long saw shed with a ridge vent, a log POND (the
only standing water on the building roster, and a strong dark shape), and sawn
board stacks that are rectangles where the raw logs are circles. Circles in,
rectangles out, reading left to right across the site.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)

POND_XY = (-0.34, 0.16)
SHED_XY = (0.14, 0.10)


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    dirt_mat = flat_material("Dirt", (0.427, 0.373, 0.278), alpha=0.84)
    track_mat = flat_material("Track", (0.529, 0.463, 0.349), alpha=0.92)
    water_mat = flat_material("Pond", (0.216, 0.286, 0.318), alpha=0.92)
    log_mat = flat_material("Log", (0.545, 0.408, 0.243))
    board_mat = flat_material("Board", (0.702, 0.588, 0.404))

    ground_patch(dirt_mat, (0.06, -0.04, 0.002), radius_x=0.56, radius_y=0.48,
                 sides=15, jitter=0.22, seed=1021, name="MillYard")

    # Log pond: floating trunks waiting to be cut.
    ground_patch(water_mat, (POND_XY[0], POND_XY[1], 0.004), radius_x=0.24,
                 radius_y=0.22, sides=12, jitter=0.18, seed=1031, name="Pond")
    for i in range(4):
        part(bpy.ops.mesh.primitive_cylinder_add, log_mat,
             (POND_XY[0] - 0.12 + i * 0.075, POND_XY[1] + 0.02, 0.030),
             radius=0.033, depth=0.026)

    path(track_mat, [POND_XY, (-0.08, 0.10), SHED_XY], width=0.12, seed=1033)
    path(track_mat, [SHED_XY, (0.26, -0.18), (0.30, -0.36)], width=0.10, seed=1039)

    # Saw shed: long, ridge-vented, the mill itself.
    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (SHED_XY[0], SHED_XY[1], 0.09),
         scale=(0.42, 0.50, 0.16), size=1.0)
    hip_roof(timber_mat, (SHED_XY[0], SHED_XY[1], 0.17), width=0.40, depth=0.48,
             height=0.15, ridge_fraction=0.64)
    part(bpy.ops.mesh.primitive_cube_add, shaft_mat, (SHED_XY[0], SHED_XY[1], 0.325),
         scale=(0.10, 0.26, 0.025), size=1.0)

    # Sawn board stacks — rectangles, against the pond's circles.
    for row in range(2):
        for col in range(3):
            part(bpy.ops.mesh.primitive_cube_add, board_mat,
                 (0.16 + col * 0.10, -0.34 - row * 0.090, 0.040),
                 scale=(0.080, 0.070, 0.045), size=1.0)
