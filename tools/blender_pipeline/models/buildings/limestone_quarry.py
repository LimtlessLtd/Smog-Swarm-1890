"""assets/buildings/limestone_quarry.png — GameEnums.BuildingType.
LIMESTONE_QUARRY, Tier 1 Industry & Extraction. A stepped open quarry cut
— terraced rock ledges — distinct from clay_pit.py's smooth round pit by
being angular/stepped and pale grey-white rather than a brown clay bowl.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STONE_LIGHT_COLOR = (0.874, 0.832, 0.709)
STONE_MID_COLOR = (0.694, 0.654, 0.554)
STONE_DARK_COLOR = (0.47, 0.432, 0.356)


def build():
    light_mat = flat_material("StoneLight", STONE_LIGHT_COLOR)
    mid_mat = flat_material("StoneMid", STONE_MID_COLOR)
    dark_mat = flat_material("StoneDark", STONE_DARK_COLOR)

    # Three stepped terraces, each smaller and lower than the last —
    # reads as a real quarry cut, not a flat pit.
    part(bpy.ops.mesh.primitive_cylinder_add, dark_mat, (0, 0, 0.0), scale=(1.0, 1.0, 0.06), radius=0.55, depth=0.1)
    part(bpy.ops.mesh.primitive_cylinder_add, mid_mat, (0, 0, 0.04), scale=(1.0, 1.0, 0.06), radius=0.4, depth=0.1)
    part(bpy.ops.mesh.primitive_cylinder_add, light_mat, (0, 0, 0.08), scale=(1.0, 1.0, 0.06), radius=0.25, depth=0.1)

    # Angular limestone block spoil pile beside the quarry.
    for i, (x, y) in enumerate([(0.4, 0.35), (0.48, 0.22), (0.35, 0.45)]):
        part(bpy.ops.mesh.primitive_cube_add, light_mat, (x, y, 0.06),
             scale=(0.09, 0.09, 0.09), size=1.0, rotation=(0, 0, i * 0.4))
