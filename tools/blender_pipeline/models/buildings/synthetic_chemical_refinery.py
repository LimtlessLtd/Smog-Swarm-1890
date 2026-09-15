"""assets/buildings/synthetic_chemical_refinery.png — GameEnums.BuildingType.SYNTHETIC_CHEMICAL_REFINERY.

Tier 5, and the family's only ROUND-TANK site: four large storage tanks in a bunded
compound, linked by pipe runs, with a fractionating column. Tanks are big pale
circles with a rim, which is closest to the power family's cooling tower — kept
apart by there being FOUR of them, by the bund wall's straight enclosure, and by
the pipe runs, none of which a power station has.

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
    flat_material, part, roof_vent, ring, ground_patch, path,
    family_materials,
)

TANKS = ((-0.30, 0.22), (0.02, 0.26), (-0.28, -0.10), (0.04, -0.06))


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.475, 0.490, 0.515))
    ground_mat = flat_material("Ash", (0.196, 0.196, 0.188), alpha=0.86)
    bund_mat = flat_material("Bund", (0.400, 0.396, 0.376), alpha=0.92)
    tank_mat = flat_material("Tank", (0.620, 0.631, 0.612))
    pipe_mat = flat_material("Pipe", (0.541, 0.404, 0.176))

    ground_patch(ground_mat, (-0.10, 0.06, 0.002), radius_x=0.56, radius_y=0.50,
                 sides=15, jitter=0.18, seed=1201, name="Compound")
    ground_patch(bund_mat, (-0.13, 0.08, 0.004), radius_x=0.42, radius_y=0.38,
                 sides=13, jitter=0.10, seed=1213, name="Bund")

    for i, (tx, ty) in enumerate(TANKS):
        part(bpy.ops.mesh.primitive_cylinder_add, tank_mat, (tx, ty, 0.13),
             radius=0.145, depth=0.26)
        ring(steel_mat, (tx, ty, 0.265), outer=0.135, thickness=0.020, height=0.03)

    # Pipe runs between the tanks and out to the column — bright copper, the
    # only warm line work in the family.
    path(pipe_mat, [TANKS[0], TANKS[1]], width=0.035, jitter=0.05, z=0.28, seed=1217)
    path(pipe_mat, [TANKS[2], TANKS[3]], width=0.035, jitter=0.05, z=0.28, seed=1223)
    path(pipe_mat, [TANKS[1], (0.22, 0.10), (0.34, -0.14)], width=0.035, jitter=0.05,
         z=0.28, seed=1229)

    # Fractionating column: a tall narrow cylinder with a hot vent, off to one side.
    part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (0.38, -0.22, 0.24),
         radius=0.095, depth=0.48)
    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (0.38, -0.22, 0.49),
         radius=0.050, depth=0.03)
    roof_vent(steel_mat, (0.14, -0.38, 0.18), radius=0.055, height=0.34)
