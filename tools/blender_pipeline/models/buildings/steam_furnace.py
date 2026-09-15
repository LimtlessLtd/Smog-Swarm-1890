"""assets/buildings/steam_furnace.png — GameEnums.BuildingType.STEAM_FURNACE.

Tier 0, the first heavy building the player gets, and deliberately the SIMPLEST
shape in the family: one squat furnace drum with a glowing top, one small shed,
one stack. Every later heavy building adds vessels, stacks or sheds to this, so
tier reads as accumulated clutter — a Tier 0 site should look nearly empty next
to bessemer_smelting_complex.

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

FURNACE_XY = (-0.06, 0.12)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    iron_mat = flat_material("Iron", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.196, 0.188, 0.180), alpha=0.86)
    track_mat = flat_material("Clinker", (0.345, 0.325, 0.298), alpha=0.92)

    ground_patch(ground_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.002), radius_x=0.40,
                 radius_y=0.38, sides=12, jitter=0.24, seed=1101, name="Yard")
    ground_patch(ground_mat, (0.26, -0.28, 0.002), radius_x=0.24, radius_y=0.20,
                 sides=10, jitter=0.28, seed=1109, name="ShedGround")
    path(track_mat, [FURNACE_XY, (0.14, -0.10), (0.26, -0.24)], width=0.10, seed=1117)

    # The furnace: one drum, one hot mouth.
    part(bpy.ops.mesh.primitive_cylinder_add, iron_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.15),
         radius=0.23, depth=0.30)
    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.305),
         radius=0.13, depth=0.03)
    roof_vent(iron_mat, (-0.30, -0.18, 0.18), radius=0.070, height=0.34)

    part(bpy.ops.mesh.primitive_cube_add, iron_mat, (0.28, -0.28, 0.07),
         scale=(0.24, 0.22, 0.12), size=1.0)
    hip_roof(roof_mat, (0.28, -0.28, 0.13), width=0.22, depth=0.20,
             height=0.11, ridge_fraction=0.45)
