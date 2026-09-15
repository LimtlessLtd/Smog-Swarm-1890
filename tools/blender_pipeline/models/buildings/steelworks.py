"""assets/buildings/steelworks.png — GameEnums.BuildingType.STEELWORKS, Tier 3.

Re-authored 2026-09-15 for the straight-down camera. Shares the heavy-industry
ground, roof and glow colours with iron_foundry.py on purpose — the family should
read as one family — so the whole burden of telling them apart falls on layout,
and that separation is deliberate rather than incidental:

  iron_foundry  one casting shed, ONE round tap hole, two round stacks of
                different diameters, moulds on a sand floor, a single haul road.
  steelworks    TWO tilting converters as paired rings on a gantry line, a
                SQUARE reheat furnace mouth, four stacks in a row, ingot stacks
                in a block, and a rail spur running the length of the site.

Round-and-scattered against square-and-ranked, at the same colours.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ring, ground_patch, path,
    family_materials,
)

CONVERTER_Y = 0.30
REHEAT_XY = (-0.30, -0.14)
MILL_XY = (0.30, -0.22)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.495, 0.510, 0.540))
    ground_mat = flat_material("Ash", (0.176, 0.169, 0.161), alpha=0.88)
    rail_mat = flat_material("Rail", (0.365, 0.345, 0.318), alpha=0.92)  # See iron_foundry.py — a path within ~0.07 of its ground reads as nothing.

    ground_patch(ground_mat, (0.0, CONVERTER_Y, 0.002), radius_x=0.56, radius_y=0.26,
                 sides=13, jitter=0.20, seed=101, name="ConverterYard")
    ground_patch(ground_mat, (REHEAT_XY[0], REHEAT_XY[1], 0.002), radius_x=0.34,
                 radius_y=0.30, sides=12, jitter=0.24, seed=113, name="ReheatYard")
    ground_patch(ground_mat, (MILL_XY[0], MILL_XY[1], 0.002), radius_x=0.34,
                 radius_y=0.32, sides=12, jitter=0.24, seed=127, name="MillYard")
    ground_patch(ground_mat, (-0.04, -0.44, 0.002), radius_x=0.22, radius_y=0.14,
                 sides=10, jitter=0.30, seed=131, name="IngotGround")

    # Rail spur running the length of the works, with branches to each shop.
    # This is the logistics-looking element that a foundry does not have.
    path(rail_mat, [(-0.62, 0.06), (-0.18, 0.02), (0.22, 0.00), (0.62, -0.04)],
         width=0.12, seed=17, name="Spur")
    path(rail_mat, [(-0.30, 0.02), REHEAT_XY], width=0.09, seed=23)
    path(rail_mat, [(0.28, -0.02), MILL_XY], width=0.09, seed=29)
    path(rail_mat, [(0.0, 0.04), (0.0, 0.18), (0.0, CONVERTER_Y - 0.06)],
         width=0.09, seed=31)

    # Converter aisle: the two Bessemer vessels as paired rings on one gantry
    # line. A PAIR of rings is the steelworks' mark; the foundry has a single
    # filled circle.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0.0, CONVERTER_Y, 0.07),
         scale=(0.88, 0.30, 0.10), size=1.0)
    for x in (-0.21, 0.21):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x, CONVERTER_Y, 0.20),
             radius=0.16, depth=0.34)
        ring(glow_mat, (x, CONVERTER_Y, 0.36), outer=0.15, thickness=0.033, height=0.04)

    # Reheat furnace: a SQUARE glowing mouth, against the foundry's round one.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (REHEAT_XY[0], REHEAT_XY[1], 0.10),
         scale=(0.40, 0.34, 0.18), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, glow_mat, (REHEAT_XY[0], REHEAT_XY[1], 0.195),
         scale=(0.22, 0.19, 0.02), size=1.0)

    # Rolling mill shed, hipped, set square to the converter aisle.
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (MILL_XY[0], MILL_XY[1], 0.08),
         scale=(0.44, 0.42, 0.14), size=1.0)
    hip_roof(roof_mat, (MILL_XY[0], MILL_XY[1], 0.15), width=0.42, depth=0.40,
             height=0.15, ridge_fraction=0.55)

    # Four stacks in an even row — ranked, where the foundry's two are unequal
    # and offset.
    for i in range(4):
        roof_vent(steel_mat, (-0.50 + i * 0.10, 0.10, 0.20), radius=0.042, height=0.36)

    # Ingot stock: a grid of short bars, against the foundry's single row.
    for ix in range(3):
        for iy in range(2):
            part(bpy.ops.mesh.primitive_cube_add, steel_mat,
                 (-0.12 + ix * 0.072, -0.47 + iy * 0.070, 0.030),
                 scale=(0.050, 0.050, 0.024), size=1.0)
