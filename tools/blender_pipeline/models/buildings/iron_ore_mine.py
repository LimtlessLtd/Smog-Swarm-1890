"""assets/buildings/iron_ore_mine.png — GameEnums.BuildingType.
IRON_ORE_MINE, Tier 2 Industry & Extraction. Same headframe-over-shaft
family as coal_pithead.py but with rust-orange ore chunks instead of black
coal lumps, and a taller frame — a bigger, later-tier mine.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.42, 0.4, 0.42)
ORE_COLOR = (0.55, 0.3, 0.16)
SHAFT_COLOR = (0.38, 0.34, 0.3)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    ore_mat = flat_material("Ore", ORE_COLOR)
    shaft_mat = flat_material("Shaft", SHAFT_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, shaft_mat, (0, 0, 0.02), scale=(1.0, 1.0, 0.06), radius=0.32, depth=0.1)

    for x in (-0.17, 0.17):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x * 0.5, 0, 0.46),
             rotation=(0, x * -1.3, 0), radius=0.045, depth=0.95)
    part(bpy.ops.mesh.primitive_torus_add, steel_mat, (0, 0.08, 0.88),
         rotation=(1.5708, 0, 0), major_radius=0.11, minor_radius=0.025)

    for x, y in ((-0.42, 0.3), (0.38, -0.25), (0.44, 0.18), (-0.3, -0.35)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, ore_mat, (x, y, 0.07), segments=7, ring_count=4, radius=0.1)
