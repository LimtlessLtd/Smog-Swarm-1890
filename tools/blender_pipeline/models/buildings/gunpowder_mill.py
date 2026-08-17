"""assets/buildings/gunpowder_mill.png — GameEnums.BuildingType.
GUNPOWDER_MILL, Tier 3 Industry & Extraction. A squat windowless brick
mill (deliberately no chimney/glow — an explosives mill wouldn't have
open flame) with barrels stacked outside, distinguishing it from every
furnace/kiln building by having no fire element at all.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BRICK_COLOR = (0.47, 0.24, 0.175)
BARREL_COLOR = (0.381, 0.22, 0.074)
BAND_COLOR = (0.56, 0.488, 0.381)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    barrel_mat = flat_material("Barrel", BARREL_COLOR)
    band_mat = flat_material("Band", BAND_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, brick_mat, (0, 0, 0.16), scale=(1.0, 1.0, 1.0), radius=0.3, depth=0.32)
    part(bpy.ops.mesh.primitive_cylinder_add, brick_mat, (0, 0, 0.35), scale=(0.85, 0.85, 0.2), radius=0.28, depth=0.1)

    for i, (x, y) in enumerate([(0.4, 0.15), (0.42, -0.05), (0.35, -0.25)]):
        part(bpy.ops.mesh.primitive_cylinder_add, barrel_mat, (x, y, 0.09), radius=0.08, depth=0.18)
        part(bpy.ops.mesh.primitive_cylinder_add, band_mat, (x, y, 0.13), scale=(1.02, 1.02, 0.15), radius=0.08, depth=0.02)
