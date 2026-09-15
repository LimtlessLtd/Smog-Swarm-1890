"""assets/buildings/heavy_coal_washery_and_pulverizer.png — GameEnums.BuildingType.HEAVY_COAL_WASHERY_AND_PULVERIZER.

Tier 4. The family's WATER building: settling ponds. Three dark rectangular tanks
stepped down a slope with a washing shed above them — standing water is otherwise
only on sawmills.py, and that pond is an irregular blob on a timber site, where
these are hard-edged tanks on ash. Black coal slurry makes them the darkest
rectangles on the roster.

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

SHED_XY = (-0.22, 0.24)
PONDS = ((0.02, 0.02), (0.10, -0.16), (0.18, -0.34))


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.188, 0.180, 0.173), alpha=0.88)
    launder_mat = flat_material("Launder", (0.392, 0.376, 0.353), alpha=0.92)
    slurry_mat = flat_material("Slurry", (0.118, 0.129, 0.133))
    coal_mat = flat_material("Coal", (0.105, 0.098, 0.094))

    ground_patch(ground_mat, (-0.10, 0.02, 0.002), radius_x=0.56, radius_y=0.50,
                 sides=14, jitter=0.20, seed=1231, name="WasheryGround")

    # Washing shed with its ridge vent, feeding the ponds.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (SHED_XY[0], SHED_XY[1], 0.10),
         scale=(0.46, 0.34, 0.18), size=1.0)
    hip_roof(roof_mat, (SHED_XY[0], SHED_XY[1], 0.19), width=0.44, depth=0.32,
             height=0.14, ridge_fraction=0.62)
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (SHED_XY[0], SHED_XY[1], 0.325),
         scale=(0.26, 0.07, 0.025), size=1.0)

    # Launders (open channels) carrying wash water down the pond chain — the
    # paths on this site are literally the process.
    path(launder_mat, [(SHED_XY[0] + 0.06, SHED_XY[1] - 0.16), PONDS[0]],
         width=0.06, seed=1237)
    path(launder_mat, [PONDS[0], PONDS[1]], width=0.06, seed=1241)
    path(launder_mat, [PONDS[1], PONDS[2]], width=0.06, seed=1249)

    # Settling tanks: hard rectangles, stepped, each rimmed.
    for i, (px, py) in enumerate(PONDS):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (px, py, 0.030),
             scale=(0.38 - i * 0.03, 0.15, 0.030), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, slurry_mat, (px, py, 0.046),
             scale=(0.34 - i * 0.03, 0.115, 0.016), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coal_mat, (-0.44, -0.28, 0.07),
         radius1=0.17, radius2=0.0, depth=0.14)
    roof_vent(steel_mat, (0.06, 0.32, 0.20), radius=0.065, height=0.36)
