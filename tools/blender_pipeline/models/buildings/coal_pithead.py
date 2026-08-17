"""assets/buildings/coal_pithead.png — GameEnums.BuildingType.COAL_MINE,
Tier 1 Industry & Extraction. A headframe (winding tower) over a mine
shaft — the tall A-frame silhouette is unique to mining buildings.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.45, 0.44, 0.46)  # Lightened — the first pass's (0.22,0.21,0.22) was too close to the outline's black to read as a structure.
COAL_COLOR = (0.14, 0.13, 0.13)
SHAFT_COLOR = (0.4, 0.35, 0.3)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    coal_mat = flat_material("Coal", COAL_COLOR)
    shaft_mat = flat_material("Shaft", SHAFT_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, shaft_mat, (0, 0, 0.02), scale=(1.0, 1.0, 0.06), radius=0.3, depth=0.1)

    # A-frame headframe legs, converging at the top, with a wheel at the peak.
    for x in (-0.16, 0.16):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x * 0.5, 0, 0.4),
             rotation=(0, x * -1.3, 0), radius=0.045, depth=0.85)
    part(bpy.ops.mesh.primitive_torus_add, steel_mat, (0, 0.08, 0.78),
         rotation=(1.5708, 0, 0), major_radius=0.1, minor_radius=0.025)

    for x, y in ((-0.4, 0.3), (0.35, -0.25), (0.42, 0.15)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, coal_mat, (x, y, 0.06), segments=7, ring_count=4, radius=0.09)
