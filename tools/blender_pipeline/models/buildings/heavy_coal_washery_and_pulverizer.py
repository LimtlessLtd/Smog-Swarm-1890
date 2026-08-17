"""assets/buildings/heavy_coal_washery_and_pulverizer.png — GameEnums.
BuildingType.HEAVY_COAL_WASHERY_AND_PULVERIZER, Tier 4 Industry &
Extraction. A tall processing tower with an angled conveyor belt feeding
up into it — the diagonal conveyor is a silhouette no mine/furnace
building has, reading as "processing," not "extraction."
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

TOWER_COLOR = (0.448, 0.407, 0.365)
DARK_COLOR = (0.224, 0.203, 0.183)
COAL_COLOR = (0.14, 0.13, 0.13)


def build():
    tower_mat = flat_material("Tower", TOWER_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    coal_mat = flat_material("Coal", COAL_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, tower_mat, (0, -0.1, 0.35), radius=0.16, depth=0.7)
    part(bpy.ops.mesh.primitive_cone_add, dark_mat, (0, -0.1, 0.74), radius1=0.16, radius2=0.05, depth=0.14)

    # Conveyor: a long angled ramp running from ground level up into the tower.
    part(bpy.ops.mesh.primitive_cube_add, dark_mat, (0.15, 0.3, 0.2),
         scale=(0.08, 0.5, 0.03), size=1.0, rotation=(-0.5, 0, 0))

    for x, y in ((0.25, 0.5), (0.32, 0.42), (0.2, 0.58)):
        part(bpy.ops.mesh.primitive_uv_sphere_add, coal_mat, (x, y, 0.04), segments=6, ring_count=4, radius=0.06)
