"""assets/buildings/searchlight_tower.png — GameEnums.BuildingType.
SEARCH_LIGHT, Tier 2 Defense Works. A fixed lookout tower with a big lamp
— taller and more skeletal than watchtower.py (no enclosed lookout box,
just an open platform), with the lamp itself as the dominant visual
element rather than a small accessory.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.32, 0.3, 0.3)
PLATFORM_COLOR = (0.269, 0.225, 0.225)
LAMP_HOUSING_COLOR = (0.202, 0.181, 0.161)
LENS_COLOR = (1.0, 0.917, 0.5)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    platform_mat = flat_material("Platform", PLATFORM_COLOR)
    housing_mat = flat_material("Housing", LAMP_HOUSING_COLOR)
    lens_mat = flat_material("Lens", LENS_COLOR)

    for x in (-0.14, 0.14):
        for y in (-0.14, 0.14):
            part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x * 0.6, y * 0.6, 0.44),
                 radius=0.045, depth=0.88)

    for z in (0.2, 0.5, 0.75):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0, 0, z), scale=(0.22, 0.035, 0.035), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0, 0, z), scale=(0.035, 0.22, 0.035), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, platform_mat, (0, 0, 0.9), scale=(0.24, 0.24, 0.04), size=1.0)

    part(bpy.ops.mesh.primitive_cylinder_add, housing_mat, (0, 0.1, 1.02),
         rotation=(1.5708, 0, 0), radius=0.14, depth=0.16)
    part(bpy.ops.mesh.primitive_cylinder_add, lens_mat, (0, 0.19, 1.02),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.3), radius=0.11, depth=0.05)
