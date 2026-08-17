"""assets/walls/wall_concrete.png — Tier 2 defensive wall segment. A tall
pale reinforced-concrete slab with visible rebar/panel seams — taller and
smoother than wall_brick.py, no individual brick pattern, reading as the
most modern/heaviest of the 3 wall tiers.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CONCRETE_COLOR = (0.62, 0.6, 0.56)
CONCRETE_DARK_COLOR = (0.48, 0.46, 0.43)
STEEL_COLOR = (0.3, 0.29, 0.3)


def build():
    concrete_mat = flat_material("Concrete", CONCRETE_COLOR)
    dark_mat = flat_material("ConcreteDark", CONCRETE_DARK_COLOR)
    steel_mat = flat_material("Steel", STEEL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (0, 0, 0.28), scale=(1.0, 0.1, 0.56), size=1.0)

    # Panel seams — vertical dividing lines breaking the slab into segments.
    for x in (-0.33, 0.0, 0.33):
        part(bpy.ops.mesh.primitive_cube_add, dark_mat, (x, 0.051, 0.28), scale=(0.008, 0.001, 0.56), size=1.0)

    # Rebar caps poking through the top.
    for x in (-0.4, -0.15, 0.15, 0.4):
        part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x, 0, 0.58), radius=0.035, depth=0.06)
