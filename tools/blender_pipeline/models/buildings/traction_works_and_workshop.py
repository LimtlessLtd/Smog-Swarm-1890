"""assets/buildings/traction_works_and_workshop.png — GameEnums.BuildingType.TRACTION_WORKS_AND_WORKSHOP.

Tier 4 unit-building works. Its mark is the ERECTING BAY: one very wide hall with
a travelling crane rail across it, and finished traction engines standing in a row
on the apron outside — small rectangles with paired wheel circles, so the site
visibly has vehicles ON it. No other building draws its own product.

Re-authored 2026-09-15 for the straight-down camera. Heavy industry shares one
palette across eleven buildings (render_common.BUILDING_FAMILY["heavy"]), so
layout carries ALL of the separation — see iron_foundry.py and steelworks.py for
the worked pair that establishes how.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ground_patch, path,
    family_materials,
)

HALL_XY = (-0.12, 0.18)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.495, 0.510, 0.540))
    ground_mat = flat_material("Ash", (0.208, 0.200, 0.192), alpha=0.86)
    apron_mat = flat_material("Apron", (0.400, 0.392, 0.376), alpha=0.92)
    engine_mat = flat_material("Engine", (0.396, 0.278, 0.204))
    wheel_mat = flat_material("Wheel", (0.184, 0.176, 0.169))

    ground_patch(ground_mat, (HALL_XY[0], HALL_XY[1], 0.002), radius_x=0.52,
                 radius_y=0.34, sides=14, jitter=0.18, seed=1321, name="WorksGround")
    ground_patch(apron_mat, (0.02, -0.28, 0.003), radius_x=0.50, radius_y=0.20,
                 sides=13, jitter=0.20, seed=1327, name="Apron")
    path(apron_mat, [(HALL_XY[0], HALL_XY[1] - 0.20), (-0.06, -0.10), (0.02, -0.22)],
         width=0.14, seed=1331)

    # Erecting bay: wide, low, with the crane rail crossing it.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (HALL_XY[0], HALL_XY[1], 0.10),
         scale=(0.78, 0.44, 0.18), size=1.0)
    hip_roof(roof_mat, (HALL_XY[0], HALL_XY[1], 0.19), width=0.74, depth=0.42,
             height=0.15, ridge_fraction=0.70)
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (HALL_XY[0], HALL_XY[1], 0.345),
         scale=(0.72, 0.06, 0.030), size=1.0)

    # Finished engines on the apron: body plus two wheel discs each.
    for i in range(3):
        ex = -0.26 + i * 0.28
        part(bpy.ops.mesh.primitive_cube_add, engine_mat, (ex, -0.28, 0.055),
             scale=(0.15, 0.09, 0.075), size=1.0)
        for side in (-1, 1):
            part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat,
                 (ex + 0.055 * side, -0.28, 0.062), radius=0.040, depth=0.070)

    roof_vent(steel_mat, (0.40, 0.24, 0.20), radius=0.065, height=0.36)
