"""assets/buildings/mechanized_maintenance_depot.png — GameEnums.BuildingType.MECHANIZED_MAINTENANCE_DEPOT.

Tier 4. The family's ROUNDHOUSE: a semicircular shed of radiating bays around a
turning circle. A fan of wedges is a shape nothing else on the roster has, and it
reads instantly as a place machines are worked on rather than a place things are
made. Distinct from macadamized_transport_hub's turntable because the fan of bays
is the building, not a fitting in a rail yard.

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
    flat_material, part, hip_roof, roof_vent, ground_patch,
    family_materials,
)

HUB_XY = (-0.04, 0.06)
BAY_COUNT = 6


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.495, 0.510, 0.540))
    ground_mat = flat_material("Ash", (0.208, 0.204, 0.196), alpha=0.86)
    apron_mat = flat_material("Apron", (0.388, 0.380, 0.365), alpha=0.92)
    pit_mat = flat_material("Pit", (0.153, 0.149, 0.145))

    ground_patch(ground_mat, (HUB_XY[0], HUB_XY[1], 0.002), radius_x=0.56,
                 radius_y=0.52, sides=15, jitter=0.18, seed=1361, name="DepotGround")
    ground_patch(apron_mat, (HUB_XY[0], HUB_XY[1] - 0.06, 0.003), radius_x=0.30,
                 radius_y=0.28, sides=12, jitter=0.12, seed=1367, name="Apron")

    # Radiating bays over the top half of the circle.
    for i in range(BAY_COUNT):
        angle = math.pi * (0.10 + 0.80 * i / (BAY_COUNT - 1))
        bx = HUB_XY[0] + math.cos(angle) * 0.34
        by = HUB_XY[1] + math.sin(angle) * 0.34
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (bx, by, 0.09),
             rotation=(0.0, 0.0, angle), scale=(0.34, 0.15, 0.16), size=1.0)
        hip_roof(roof_mat, (bx, by, 0.17), width=0.32, depth=0.13,
                 height=0.11, ridge_fraction=0.70, name="Bay%d" % i)
        # Inspection pit inside each bay, pointing at the hub.
        part(bpy.ops.mesh.primitive_cube_add, pit_mat, (bx, by, 0.175),
             rotation=(0.0, 0.0, angle), scale=(0.24, 0.045, 0.02), size=1.0)

    # Turning circle at the hub.
    part(bpy.ops.mesh.primitive_cylinder_add, pit_mat, (HUB_XY[0], HUB_XY[1], 0.010),
         radius=0.155, depth=0.016)
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (HUB_XY[0], HUB_XY[1], 0.020),
         scale=(0.30, 0.030, 0.014), size=1.0)
    roof_vent(steel_mat, (0.42, -0.26, 0.18), radius=0.055, height=0.32)
