"""assets/buildings/armory_and_barracks.png — GameEnums.BuildingType.
ARMORY_AND_BARRACKS, Tier 2 Housing & Civil. A long barracks hall with
racked rifles out front — bigger and more militarized than garrison.py
(no palisade ring here; this is a training/quartering hall, not a fort),
distinguished by the visible weapon rack silhouette.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WALL_COLOR = (0.56, 0.488, 0.381)   # Lightened — first pass was too close in value to the roof/outline to read as a distinct wall.
ROOF_COLOR = (0.314, 0.245, 0.177)
RIFLE_COLOR = (0.448, 0.318, 0.123)


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    rifle_mat = flat_material("Rifle", RIFLE_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (0, -0.05, 0.18), scale=(0.55, 0.28, 0.18), size=1.0)
    gable_roof(roof_mat, (0, -0.05, 0.36), width=0.6, depth=0.32, height=0.18, ridge_along_y=False)

    # Weapon rack: a row of angled rifles leaning against a rail — radius
    # 0.035 minimum per this pipeline's own established rule (thinner gets
    # swallowed by the Freestyle outline, see README's "Minimum part thickness").
    part(bpy.ops.mesh.primitive_cube_add, rifle_mat, (0.15, 0.28, 0.06), scale=(0.32, 0.02, 0.02), size=1.0)
    for i in range(5):
        x = 0.0 + i * 0.06
        part(bpy.ops.mesh.primitive_cylinder_add, rifle_mat, (x, 0.32, 0.16),
             rotation=(0.25, 0, 0), radius=0.035, depth=0.26)
