"""assets/buildings/steam_turbine_power_plant.png — GameEnums.BuildingType.STEAM_TURBINE_POWER_PLANT.

Tier 4. Breaks the family's tower-count progression on purpose: a turbine plant is
a CONDENSER site, so instead of more cooling towers it gets one very large tower
and a bank of four condenser drums in a row. Big-single-plus-row, against
advanced_coal_powerplant's matched pair — otherwise Tier 3 and Tier 4 would differ
only by counting rings, which is not readable at map zoom.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ring, ground_patch, path,
    family_materials,
)

HALL_XY = (-0.26, 0.06)
TOWER_XY = (0.30, 0.20)


def build():
    concrete_mat, roof_mat, steam_mat = family_materials("power")
    void_mat = flat_material("TowerVoid", (0.145, 0.153, 0.165))
    drum_mat = flat_material("Condenser", (0.565, 0.588, 0.612))
    apron_mat = flat_material("Apron", (0.545, 0.541, 0.522), alpha=0.86)
    haul_mat = flat_material("Haul", (0.435, 0.427, 0.408), alpha=0.90)

    ground_patch(apron_mat, (HALL_XY[0], HALL_XY[1], 0.002), radius_x=0.42,
                 radius_y=0.46, sides=14, jitter=0.18, seed=1441, name="HallApron")
    ground_patch(apron_mat, (TOWER_XY[0], TOWER_XY[1], 0.002), radius_x=0.36,
                 radius_y=0.34, sides=13, jitter=0.18, seed=1447, name="TowerApron")
    ground_patch(apron_mat, (0.06, -0.34, 0.002), radius_x=0.46, radius_y=0.18,
                 sides=12, jitter=0.24, seed=1451, name="CondenserGround")

    path(haul_mat, [HALL_XY, (0.02, 0.14), TOWER_XY], width=0.12, seed=1453)
    path(haul_mat, [(-0.24, -0.18), (-0.06, -0.30), (0.22, -0.34)], width=0.10, seed=1459)

    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (HALL_XY[0], HALL_XY[1], 0.10),
         scale=(0.46, 0.66, 0.18), size=1.0)
    hip_roof(roof_mat, (HALL_XY[0], HALL_XY[1], 0.19), width=0.44, depth=0.62,
             height=0.16, ridge_fraction=0.70)
    part(bpy.ops.mesh.primitive_cube_add, roof_mat, (HALL_XY[0], HALL_XY[1], 0.345),
         scale=(0.09, 0.34, 0.025), size=1.0)

    # One oversized cooling tower.
    part(bpy.ops.mesh.primitive_cylinder_add, void_mat, (TOWER_XY[0], TOWER_XY[1], 0.15),
         radius=0.28, depth=0.28)
    ring(steam_mat, (TOWER_XY[0], TOWER_XY[1], 0.30), outer=0.32, thickness=0.058, height=0.11)

    # Condenser bank: four drums in a row, the Tier 4 mark.
    for i in range(4):
        part(bpy.ops.mesh.primitive_cylinder_add, drum_mat,
             (-0.24 + i * 0.20, -0.34, 0.09), rotation=(0.0, 1.5708, 0.0),
             radius=0.075, depth=0.17)
