"""assets/buildings/advanced_coal_powerplant.png — GameEnums.BuildingType.ADVANCED_COAL_POWERPLANT.

Tier 3. coal_powerplant with TWO cooling towers instead of one and a longer
turbine hall — tower count is the power family's tier, the same way converter
count is heavy industry's. A player should read this as the Tier 1 plant grown,
not as an unrelated building.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ring, ground_patch, path,
    family_materials,
)

HALL_XY = (-0.28, 0.02)
TOWERS = ((0.28, 0.26), (0.30, -0.18))


def build():
    concrete_mat, roof_mat, steam_mat = family_materials("power")
    void_mat = flat_material("TowerVoid", (0.145, 0.153, 0.165))
    coal_mat = flat_material("Coal", (0.105, 0.098, 0.094))
    apron_mat = flat_material("Apron", (0.545, 0.541, 0.522), alpha=0.86)
    haul_mat = flat_material("Haul", (0.435, 0.427, 0.408), alpha=0.90)

    ground_patch(apron_mat, (HALL_XY[0], HALL_XY[1], 0.002), radius_x=0.40,
                 radius_y=0.48, sides=14, jitter=0.18, seed=1401, name="HallApron")
    for i, (tx, ty) in enumerate(TOWERS):
        ground_patch(apron_mat, (tx, ty, 0.002), radius_x=0.30, radius_y=0.28,
                     sides=12, jitter=0.20, seed=1411 + i * 7, name="TowerApron%d" % i)
    ground_patch(apron_mat, (-0.26, -0.42, 0.002), radius_x=0.26, radius_y=0.16,
                 sides=10, jitter=0.30, seed=1427, name="StockGround")

    path(haul_mat, [HALL_XY, (0.02, 0.14), TOWERS[0]], width=0.11, seed=1429)
    path(haul_mat, [HALL_XY, (0.02, -0.12), TOWERS[1]], width=0.11, seed=1433)
    path(haul_mat, [(-0.28, -0.22), (-0.26, -0.38)], width=0.10, seed=1439)

    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (HALL_XY[0], HALL_XY[1], 0.09),
         scale=(0.46, 0.76, 0.16), size=1.0)
    hip_roof(roof_mat, (HALL_XY[0], HALL_XY[1], 0.17), width=0.44, depth=0.72,
             height=0.15, ridge_fraction=0.72)
    part(bpy.ops.mesh.primitive_cube_add, roof_mat, (HALL_XY[0], HALL_XY[1], 0.315),
         scale=(0.09, 0.38, 0.025), size=1.0)

    for tx, ty in TOWERS:
        part(bpy.ops.mesh.primitive_cylinder_add, void_mat, (tx, ty, 0.14),
             radius=0.215, depth=0.26)
        ring(steam_mat, (tx, ty, 0.28), outer=0.255, thickness=0.050, height=0.10)

    roof_vent(roof_mat, (-0.02, -0.40, 0.20), radius=0.070, height=0.36)
    part(bpy.ops.mesh.primitive_cone_add, coal_mat, (-0.26, -0.42, 0.06),
         radius1=0.14, radius2=0.0, depth=0.13)
