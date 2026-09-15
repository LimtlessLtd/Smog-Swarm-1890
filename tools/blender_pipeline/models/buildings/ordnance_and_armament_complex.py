"""assets/buildings/ordnance_and_armament_complex.png — GameEnums.BuildingType.ORDNANCE_AND_ARMAMENT_COMPLEX.

Tier 5. The family's LONG-SHED building: three parallel machine halls of equal
length under saw-tooth ridge vents, with a proof range running off one end —
a straight barrel-testing line with butts at the far end. Parallel equal halls is
a regimented layout no other heavy site uses; everything else is clustered or
strung along a road.

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

HALL_XS = (-0.32, -0.04, 0.24)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.495, 0.510, 0.540))
    ground_mat = flat_material("Ash", (0.196, 0.192, 0.184), alpha=0.88)
    road_mat = flat_material("Road", (0.376, 0.365, 0.345), alpha=0.92)
    butt_mat = flat_material("Butt", (0.365, 0.333, 0.271), alpha=0.94)

    ground_patch(ground_mat, (-0.04, 0.10, 0.002), radius_x=0.58, radius_y=0.44,
                 sides=15, jitter=0.16, seed=1307, name="WorksGround")

    # Service road across the ends of all three halls.
    path(road_mat, [(-0.56, -0.20), (-0.04, -0.22), (0.50, -0.18)], width=0.12, seed=1311)

    for i, x in enumerate(HALL_XS):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (x, 0.14, 0.09),
             scale=(0.22, 0.60, 0.16), size=1.0)
        hip_roof(roof_mat, (x, 0.14, 0.17), width=0.20, depth=0.58,
                 height=0.13, ridge_fraction=0.30, name="Hall%d" % i)
        # Saw-tooth roof lights along each ridge.
        for j in range(4):
            part(bpy.ops.mesh.primitive_cube_add, steel_mat, (x, -0.06 + j * 0.13, 0.305),
                 scale=(0.13, 0.045, 0.022), size=1.0)

    # Proof range: a straight run with earth butts at the end.
    path(butt_mat, [(0.46, 0.34), (0.52, 0.06), (0.54, -0.24)], width=0.10, seed=1319)
    part(bpy.ops.mesh.primitive_cube_add, butt_mat, (0.54, -0.34, 0.055),
         scale=(0.20, 0.09, 0.09), size=1.0)
    roof_vent(steel_mat, (-0.52, -0.02, 0.20), radius=0.060, height=0.36)
