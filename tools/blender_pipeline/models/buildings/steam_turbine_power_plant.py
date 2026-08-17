"""assets/buildings/steam_turbine_power_plant.png — GameEnums.BuildingType.
STEAM_TURBINE_POWER_PLANT, Tier 4 Industry & Extraction. A single massive
central chimney (bigger than any earlier power building's chimneys) rising
from a wide round turbine housing — reads as one dominant machine, not a
shed-plus-stacks layout like coal_powerplant.py/advanced_coal_powerplant.py.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

HOUSING_COLOR = (0.42, 0.4, 0.4)
DARK_COLOR = (0.22, 0.21, 0.21)
STEAM_COLOR = (0.85, 0.85, 0.85)


def build():
    housing_mat = flat_material("Housing", HOUSING_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    steam_mat = flat_material("Steam", STEAM_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, housing_mat, (0, 0, 0.14), radius=0.36, depth=0.28)
    chimney(dark_mat, (0, 0, 0.75), height=0.65, radius=0.11)

    # Steam puffs — small pale spheres near the chimney top, a "this is
    # active" flourish.
    for x, y, z in ((0.06, 0.1, 1.15), (-0.05, -0.08, 1.22)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, steam_mat, (x, y, z), scale=(1.0, 1.0, 0.7), segments=7, ring_count=4, radius=0.08)
