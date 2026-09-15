"""assets/buildings/central_high_voltage_grid_station.png — GameEnums.BuildingType.CENTRAL_HIGH_VOLTAGE_GRID_STATION.

Tier 5, and the family's only site with NO cooling tower and NO chimney: a
switchyard is an open compound of busbar gantries and transformer blocks. A grid
of thin parallel lines with squat squares under them is the least building-like
thing on the roster, which is right — it is infrastructure, not a works — and it
guarantees no confusion with the two generating plants.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, rail_lines,
    family_materials,
)


def build():
    concrete_mat, roof_mat, steam_mat = family_materials("power")
    apron_mat = flat_material("Apron", (0.553, 0.549, 0.533), alpha=0.86)
    gravel_mat = flat_material("Gravel", (0.463, 0.459, 0.443), alpha=0.92)
    steel_mat = flat_material("Steel", (0.478, 0.494, 0.522))
    tank_mat = flat_material("Transformer", (0.365, 0.376, 0.396))

    ground_patch(apron_mat, (0.0, 0.04, 0.002), radius_x=0.60, radius_y=0.50,
                 sides=15, jitter=0.16, seed=1461, name="Switchyard")

    # Busbar runs: three long parallel conductors across the compound, on
    # gantry legs. The lines ARE the building.
    rail_lines(steel_mat, count=3, length=1.10, z=0.008, spacing=0.20, thickness=0.020)
    for row in range(3):
        y = -0.20 + row * 0.20
        for x in (-0.50, -0.16, 0.18, 0.50):
            part(bpy.ops.mesh.primitive_cube_add, steel_mat, (x, y, 0.13),
                 scale=(0.040, 0.040, 0.26), size=1.0)

    # Transformer blocks beneath, each with a bank of cooling fins.
    for i, (tx, ty) in enumerate(((-0.34, 0.06), (0.02, 0.06), (0.38, 0.06))):
        part(bpy.ops.mesh.primitive_cube_add, tank_mat, (tx, ty, 0.08),
             scale=(0.20, 0.16, 0.16), size=1.0)
        for j in range(4):
            part(bpy.ops.mesh.primitive_cube_add, steel_mat,
                 (tx - 0.06 + j * 0.04, ty - 0.10, 0.085),
                 scale=(0.016, 0.055, 0.15), size=1.0)

    # Access road round the compound edge, and a small control hut.
    path(gravel_mat, [(-0.60, -0.34), (0.0, -0.38), (0.58, -0.32)], width=0.10, seed=1471)
    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (-0.44, -0.34, 0.06),
         scale=(0.18, 0.15, 0.11), size=1.0)
    hip_roof(roof_mat, (-0.44, -0.34, 0.115), width=0.16, depth=0.13,
             height=0.09, ridge_fraction=0.40)
