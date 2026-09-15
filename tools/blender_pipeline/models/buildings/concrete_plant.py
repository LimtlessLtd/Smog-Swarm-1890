"""assets/buildings/concrete_plant.png — GameEnums.BuildingType.CONCRETE_PLANT.

The family's SILO-AND-HOPPER building: three tall batching silos in a tight
triangle over a mixer, with aggregate bays around them. Three pale circles
clustered is distinct from brickworks' five domes in a line and from steelworks'
two rings on a bar — cluster versus row versus pair, at the same colours.

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
    flat_material, part, ground_patch, path, family_materials,
)

MIXER_XY = (-0.10, 0.10)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    iron_mat = flat_material("Iron", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.208, 0.200, 0.192), alpha=0.86)
    track_mat = flat_material("Haul", (0.365, 0.345, 0.325), alpha=0.92)
    silo_mat = flat_material("Silo", (0.678, 0.667, 0.639))
    agg_mat = flat_material("Aggregate", (0.502, 0.478, 0.443))

    ground_patch(ground_mat, (MIXER_XY[0], MIXER_XY[1], 0.002), radius_x=0.46,
                 radius_y=0.42, sides=13, jitter=0.20, seed=1141, name="PlantGround")
    ground_patch(ground_mat, (0.28, -0.32, 0.002), radius_x=0.34, radius_y=0.20,
                 sides=11, jitter=0.28, seed=1151, name="BayGround")
    path(track_mat, [(-0.56, -0.24), (-0.16, -0.16), (0.22, -0.28)], width=0.13, seed=1153)

    # Three batching silos in a triangle over the mixer house.
    part(bpy.ops.mesh.primitive_cube_add, iron_mat, (MIXER_XY[0], MIXER_XY[1], 0.09),
         scale=(0.42, 0.40, 0.16), size=1.0)
    for dx, dy in ((-0.13, 0.11), (0.13, 0.11), (0.0, -0.12)):
        part(bpy.ops.mesh.primitive_cylinder_add, silo_mat,
             (MIXER_XY[0] + dx, MIXER_XY[1] + dy, 0.26), radius=0.115, depth=0.44)
        part(bpy.ops.mesh.primitive_cylinder_add, iron_mat,
             (MIXER_XY[0] + dx, MIXER_XY[1] + dy, 0.485), radius=0.055, depth=0.03)

    # Aggregate bays: open-fronted stalls of sand and stone.
    for i in range(3):
        part(bpy.ops.mesh.primitive_cube_add, agg_mat, (0.10 + i * 0.16, -0.32, 0.045),
             scale=(0.14, 0.18, 0.055), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, iron_mat, (0.18 + i * 0.16, -0.32, 0.060),
             scale=(0.014, 0.19, 0.075), size=1.0)
