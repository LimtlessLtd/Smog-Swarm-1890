"""assets/buildings/bessemer_smelting_complex.png — GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX.

Tier 5, the top of the family, and deliberately steelworks.py scaled up: FOUR
converters instead of two, a double gantry, six stacks, and a rail loop rather
than a single spur. A player who knows the Tier 3 steelworks should read this as
the same plant grown, which is what the roster means by "complex" — the tier is
the count, not a new vocabulary.

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
    flat_material, part, hip_roof, roof_vent, ring, ground_patch, path,
    family_materials,
)

GANTRY_Y = 0.30


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.495, 0.510, 0.540))
    ground_mat = flat_material("Ash", (0.176, 0.169, 0.161), alpha=0.90)
    rail_mat = flat_material("Rail", (0.365, 0.345, 0.318), alpha=0.92)

    ground_patch(ground_mat, (0.0, GANTRY_Y, 0.002), radius_x=0.62, radius_y=0.26,
                 sides=15, jitter=0.16, seed=1161, name="ConverterGround")
    ground_patch(ground_mat, (-0.26, -0.18, 0.002), radius_x=0.40, radius_y=0.34,
                 sides=13, jitter=0.22, seed=1171, name="CastGround")
    ground_patch(ground_mat, (0.34, -0.22, 0.002), radius_x=0.34, radius_y=0.32,
                 sides=12, jitter=0.24, seed=1181, name="MillGround")

    # Rail loop rather than a spur — the Tier 5 marker at ground level.
    path(rail_mat, [(-0.62, 0.02), (-0.20, -0.02), (0.24, -0.02), (0.62, 0.04)],
         width=0.12, seed=1187, name="LoopNorth")
    path(rail_mat, [(-0.62, 0.02), (-0.56, -0.30), (-0.10, -0.44), (0.40, -0.42),
                    (0.62, -0.18), (0.62, 0.04)], width=0.10, seed=1193, name="LoopSouth")

    # Four converters on a double gantry.
    for row, y in enumerate((GANTRY_Y + 0.10, GANTRY_Y - 0.10)):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0.0, y, 0.06),
             scale=(1.00, 0.16, 0.09), size=1.0)
        for x in (-0.24, 0.24):
            part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x, y, 0.18),
                 radius=0.135, depth=0.30)
            ring(glow_mat, (x, y, 0.325), outer=0.125, thickness=0.030, height=0.04)

    # Casting house and rolling mill, each hipped.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (-0.28, -0.18, 0.09),
         scale=(0.44, 0.40, 0.16), size=1.0)
    hip_roof(roof_mat, (-0.28, -0.18, 0.17), width=0.42, depth=0.38,
             height=0.15, ridge_fraction=0.56)
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0.34, -0.22, 0.09),
         scale=(0.40, 0.38, 0.16), size=1.0)
    hip_roof(roof_mat, (0.34, -0.22, 0.17), width=0.38, depth=0.36,
             height=0.15, ridge_fraction=0.52)

    # Six stacks — steelworks has four, iron_foundry two.
    for i in range(6):
        roof_vent(steel_mat, (-0.50 + i * 0.096, 0.04, 0.20), radius=0.038, height=0.36)
