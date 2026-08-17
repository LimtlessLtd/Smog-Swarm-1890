"""assets/buildings/deep_coal_shafts.png — GameEnums.BuildingType.
DEEP_COAL_SHAFTS, Tier 3 Industry & Extraction. Twin headframes over one
shaft — a doubled-up escalation of coal_pithead.py's single frame, reading
as a bigger, later-tier version of the same mine family.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.4, 0.38, 0.4)
COAL_COLOR = (0.18, 0.17, 0.17)
SHAFT_COLOR = (0.36, 0.32, 0.28)


def _headframe(steel_mat, x_offset):
    for x in (-0.13, 0.13):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x_offset + x * 0.5, 0, 0.4),
             rotation=(0, x * -1.3, 0), radius=0.04, depth=0.82)
    part(bpy.ops.mesh.primitive_torus_add, steel_mat, (x_offset, 0.06, 0.76),
         rotation=(1.5708, 0, 0), major_radius=0.09, minor_radius=0.02)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    coal_mat = flat_material("Coal", COAL_COLOR)
    shaft_mat = flat_material("Shaft", SHAFT_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, shaft_mat, (0, 0, 0.02), scale=(1.0, 1.0, 0.06), radius=0.4, depth=0.1)

    _headframe(steel_mat, -0.2)
    _headframe(steel_mat, 0.2)

    for x, y in ((-0.5, 0.25), (0.5, -0.2), (0.0, -0.4), (-0.15, 0.4)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, coal_mat, (x, y, 0.07), segments=7, ring_count=4, radius=0.1)
