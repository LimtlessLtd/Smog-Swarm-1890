"""assets/buildings/coal_powerplant.png — GameEnums.BuildingType.COAL_POWERPLANT.

Re-authored 2026-09-15 for the straight-down camera, and the power family's
reference model. Overhead the old model was a grey box with two grey cylinders,
near-identical to steelworks and steam_turbine_power_plant.

The power signature is the cooling-tower annulus: a ring with a dark open centre,
which from directly above is unmistakable and which nothing else on the roster
draws. Per-plant identity across the family is tower count and size — one here,
more and larger at the advanced tiers.

Concrete hardstanding is laid as separate irregular aprons under the hall, the
tower and the coal stock, joined by a haul road, rather than as one slab.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ring, ground_patch, path,
    family_materials,
)

HALL_XY = (-0.26, 0.04)
TOWER_XY = (0.32, 0.20)
STOCK_XY = (-0.16, -0.40)


def build():
    concrete_mat, roof_mat, steam_mat = family_materials("power")
    void_mat = flat_material("TowerVoid", (0.145, 0.153, 0.165))
    coal_mat = flat_material("Coal", (0.105, 0.098, 0.094))
    apron_mat = flat_material("Apron", (0.545, 0.541, 0.522), alpha=0.86)
    haul_mat = flat_material("Haul", (0.435, 0.427, 0.408), alpha=0.90)

    ground_patch(apron_mat, (HALL_XY[0], HALL_XY[1], 0.002), radius_x=0.42,
                 radius_y=0.44, sides=13, jitter=0.18, seed=201, name="HallApron")
    ground_patch(apron_mat, (TOWER_XY[0], TOWER_XY[1], 0.002), radius_x=0.34,
                 radius_y=0.34, sides=12, jitter=0.20, seed=211, name="TowerApron")
    ground_patch(apron_mat, (STOCK_XY[0], STOCK_XY[1], 0.002), radius_x=0.28,
                 radius_y=0.18, sides=11, jitter=0.30, seed=223, name="StockGround")

    path(haul_mat, [HALL_XY, (0.02, 0.12), TOWER_XY], width=0.12, seed=37)
    path(haul_mat, [(-0.24, -0.16), STOCK_XY], width=0.11, seed=43)

    # Turbine hall: long, low, ridge-vented. The counterpart shape to the
    # tower — a power station from the air is a hall plus a ring.
    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (HALL_XY[0], HALL_XY[1], 0.09),
         scale=(0.52, 0.66, 0.16), size=1.0)
    hip_roof(roof_mat, (HALL_XY[0], HALL_XY[1], 0.17), width=0.48, depth=0.62,
             height=0.15, ridge_fraction=0.66)
    # Ridge vent in the roof colour, not the family accent: at full accent
    # brightness it read as a glowing strip and competed with the cooling tower
    # for attention. The accent is reserved for the tower rim, which is the
    # shape that actually identifies the family.
    part(bpy.ops.mesh.primitive_cube_add, roof_mat, (HALL_XY[0], HALL_XY[1], 0.315),
         scale=(0.24, 0.07, 0.025), size=1.0)

    # Cooling tower: the family signature. Dark void inside the rim so the
    # centre reads as an opening, not a disc.
    part(bpy.ops.mesh.primitive_cylinder_add, void_mat, (TOWER_XY[0], TOWER_XY[1], 0.14),
         radius=0.25, depth=0.26)
    ring(steam_mat, (TOWER_XY[0], TOWER_XY[1], 0.28), outer=0.29, thickness=0.053, height=0.10)

    # Boiler house chimney: one tall stack, smaller than a heavy-industry one so
    # power does not read as a foundry.
    roof_vent(roof_mat, (0.28, -0.26, 0.22), radius=0.080, height=0.40)

    # Coal stock: a dark heap on the concrete, the fuel that says "coal" plant.
    part(bpy.ops.mesh.primitive_cone_add, coal_mat, (STOCK_XY[0], STOCK_XY[1], 0.06),
         radius1=0.16, radius2=0.0, depth=0.14)
