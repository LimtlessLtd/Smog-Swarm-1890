"""assets/buildings/steam_excavator_depot.png — GameEnums.BuildingType.STEAM_EXCAVATOR_DEPOT.

Tier 4. Reads as a MACHINE YARD rather than a factory: an open hardstanding with
excavators parked around a small repair shed, each drawn as a body with a boom
projecting outward. The booms are the signature — radiating spokes of differing
length around an open yard, where traction_works_and_workshop lines its product up
in a neat row outside a huge hall.

Re-authored 2026-09-15 for the straight-down camera. Heavy industry shares one
palette across eleven buildings (render_common.BUILDING_FAMILY["heavy"]), so
layout carries ALL of the separation — see iron_foundry.py and steelworks.py for
the worked pair that establishes how.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)

YARD_XY = (0.0, 0.0)
MACHINES = ((-0.30, 0.26, 0.9), (0.20, 0.30, -0.6), (0.34, -0.10, -1.9), (-0.16, -0.30, 2.3))


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.216, 0.208, 0.200), alpha=0.86)
    hard_mat = flat_material("Hardstanding", (0.376, 0.369, 0.353), alpha=0.92)
    body_mat = flat_material("Body", (0.416, 0.322, 0.176))
    boom_mat = flat_material("Boom", (0.235, 0.224, 0.212))

    ground_patch(ground_mat, (0.0, 0.0, 0.002), radius_x=0.58, radius_y=0.52,
                 sides=15, jitter=0.20, seed=1337, name="Yard")
    ground_patch(hard_mat, (0.0, 0.0, 0.003), radius_x=0.40, radius_y=0.36,
                 sides=12, jitter=0.14, seed=1341, name="Hardstanding")

    # Repair shed, off to one side so the yard stays open.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (-0.36, -0.12, 0.08),
         scale=(0.26, 0.30, 0.14), size=1.0)
    hip_roof(roof_mat, (-0.36, -0.12, 0.15), width=0.24, depth=0.28,
             height=0.13, ridge_fraction=0.50)

    # Excavators: body, boom, and tracks. The booms point every which way.
    for i, (mx, my, rot) in enumerate(MACHINES):
        path(hard_mat, [(0.0, 0.0), (mx * 0.6, my * 0.6), (mx, my)], width=0.075,
             seed=1351 + i * 5, name="Route%d" % i)
        part(bpy.ops.mesh.primitive_cube_add, body_mat, (mx, my, 0.065),
             rotation=(0.0, 0.0, rot), scale=(0.15, 0.12, 0.09), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, boom_mat,
             (mx + 0.13 * math.cos(rot), my + 0.13 * math.sin(rot), 0.075),
             rotation=(0.0, 0.0, rot), scale=(0.20, 0.035, 0.030), size=1.0)
