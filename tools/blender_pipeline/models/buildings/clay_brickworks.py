"""assets/buildings/clay_brickworks.png — GameEnums.BuildingType.BRICKWORKS.

The family member with a KILN ROW: five beehive kilns in a line, each a dome with
a dark crown, plus drying racks of green bricks. Domes-in-a-row is a shape no
other heavy building uses (steelworks has two rings, sulfur has retorts at half
the size on a different palette), and the stacked brick colour is the only warm
red on a heavy-industry site.

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
    flat_material, part, roof_vent, ground_patch, path, family_materials,
)

KILN_Y = 0.22


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    iron_mat = flat_material("Iron", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.208, 0.196, 0.184), alpha=0.86)
    track_mat = flat_material("Clinker", (0.345, 0.325, 0.298), alpha=0.92)
    brick_mat = flat_material("Brick", (0.612, 0.318, 0.212))
    crown_mat = flat_material("Crown", (0.153, 0.145, 0.141))

    ground_patch(ground_mat, (0.0, KILN_Y, 0.002), radius_x=0.58, radius_y=0.22,
                 sides=14, jitter=0.18, seed=1121, name="KilnGround")
    ground_patch(ground_mat, (-0.06, -0.26, 0.002), radius_x=0.46, radius_y=0.24,
                 sides=12, jitter=0.26, seed=1129, name="DryingGround")
    path(track_mat, [(-0.44, KILN_Y - 0.14), (-0.10, -0.02), (0.18, -0.20)],
         width=0.11, seed=1133)

    # Kiln row: five domes with dark crowns.
    for i in range(5):
        x = -0.44 + i * 0.22
        part(bpy.ops.mesh.primitive_uv_sphere_add, brick_mat, (x, KILN_Y, 0.10),
             scale=(1.0, 1.0, 0.70), segments=14, ring_count=7, radius=0.10)
        part(bpy.ops.mesh.primitive_cylinder_add, crown_mat, (x, KILN_Y, 0.175),
             radius=0.030, depth=0.03)

    # Drying racks: rows of green brick stacks under open timber frames.
    for row in range(2):
        for col in range(5):
            part(bpy.ops.mesh.primitive_cube_add, brick_mat,
                 (-0.32 + col * 0.13, -0.20 - row * 0.115, 0.035),
                 scale=(0.10, 0.085, 0.040), size=1.0)

    roof_vent(iron_mat, (0.44, -0.22, 0.20), radius=0.075, height=0.38)
