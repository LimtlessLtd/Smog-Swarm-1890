"""assets/buildings/concrete_plant.png — GameEnums.BuildingType.
CONCRETE_PLANT, Tier 2 Industry & Extraction. A mixing tower with angled
hoppers feeding a drum — pale grey-white concrete tones, distinct from
every warm brick/wood industrial building around it.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CONCRETE_COLOR = (0.68, 0.66, 0.62)
CONCRETE_DARK_COLOR = (0.5, 0.48, 0.44)
STEEL_COLOR = (0.4, 0.4, 0.42)


def build():
    concrete_mat = flat_material("Concrete", CONCRETE_COLOR)
    concrete_dark_mat = flat_material("ConcreteDark", CONCRETE_DARK_COLOR)
    steel_mat = flat_material("Steel", STEEL_COLOR)

    # Tall mixing tower.
    part(bpy.ops.mesh.primitive_cylinder_add, concrete_mat, (0, 0, 0.34), radius=0.16, depth=0.68)

    # Hopper funnel on top, feeding down into the tower.
    part(bpy.ops.mesh.primitive_cone_add, concrete_dark_mat, (0, 0, 0.76), radius1=0.24, radius2=0.1, depth=0.24)

    # Mixing drum at the base, tilted.
    part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (0.24, 0.05, 0.14),
         rotation=(0, 1.2, 0.2), scale=(1.0, 1.0, 1.0), radius=0.13, depth=0.32)

    # Support legs.
    for x, y in ((-0.1, -0.1), (0.1, -0.1), (-0.1, 0.1), (0.1, 0.1)):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x, y, 0.0), radius=0.02, depth=0.02)
