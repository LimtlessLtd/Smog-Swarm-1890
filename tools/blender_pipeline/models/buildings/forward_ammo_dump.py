"""assets/buildings/forward_ammo_dump.png — GameEnums.BuildingType.
SUPPLY_DUMP, Tier 1 Industry & Extraction. Stacked crates under a simple
tarp canopy — low, wide, and cluttered rather than a single tall
structure, reading as a storage/logistics site rather than a building at all.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CRATE_COLOR = (0.47, 0.309, 0.084)
CRATE_DARK_COLOR = (0.336, 0.208, 0.047)
TARP_COLOR = (0.237, 0.358, 0.22)


def build():
    crate_mat = flat_material("Crate", CRATE_COLOR)
    crate_dark_mat = flat_material("CrateDark", CRATE_DARK_COLOR)
    tarp_mat = flat_material("Tarp", TARP_COLOR)

    # A cluster of crates at varied sizes/rotations — deliberately
    # irregular, not a neat grid, so it reads as a hasty depot.
    crates = [
        (-0.2, -0.1, 0.08, 0.16, 0.1),
        (0.05, -0.05, 0.06, 0.12, 0.05),
        (-0.05, 0.15, 0.07, 0.14, 0.15),
        (0.25, 0.05, 0.09, 0.18, -0.1),
        (0.15, -0.25, 0.06, 0.12, 0.25),
    ]
    for i, (x, y, size, height, rot) in enumerate(crates):
        mat = crate_dark_mat if i % 2 else crate_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, y, height / 2.0),
             scale=(size, size, height), size=1.0, rotation=(0, 0, rot))

    # Tarp canopy over part of the pile.
    part(bpy.ops.mesh.primitive_cube_add, tarp_mat, (-0.1, 0.0, 0.2),
         scale=(0.4, 0.32, 0.02), size=1.0, rotation=(0.1, 0.05, 0))
