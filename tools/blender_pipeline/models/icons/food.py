"""assets/icons/food.png — GameEnums.ResourceType.FOOD. A loaf of bread
and a wedge of cheese — same subject the old AI-prompt README specified,
built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BREAD_COLOR = (0.68, 0.44, 0.2)
CRUST_COLOR = (0.5, 0.3, 0.13)
CHEESE_COLOR = (0.9, 0.78, 0.3)


def build():
    bread_mat = flat_material("Bread", BREAD_COLOR)
    crust_mat = flat_material("Crust", CRUST_COLOR)
    cheese_mat = flat_material("Cheese", CHEESE_COLOR)

    part(bpy.ops.mesh.primitive_uv_sphere_add, bread_mat, (-0.15, 0, 0.1),
         scale=(1.3, 0.9, 0.7), segments=10, ring_count=6, radius=0.22)
    for i in range(3):
        part(bpy.ops.mesh.primitive_cube_add, crust_mat, (-0.15 + i * 0.1 - 0.1, 0, 0.22),
             scale=(0.02, 0.2, 0.02), size=1.0)

    # Wedge: a triangular-based cone (vertices=3) lying on its side — the
    # closest primitive approximation of a cheese wedge's shape.
    part(bpy.ops.mesh.primitive_cone_add, cheese_mat, (0.28, 0, 0.08),
         vertices=3, radius1=0.18, radius2=0.18, depth=0.2, rotation=(0, 1.5708, 0.5))
