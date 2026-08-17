"""assets/icons/concrete.png — GameEnums.ResourceType.CONCRETE. A pale
grey concrete slab — same subject as the old AI-prompt README, built from
primitives instead. A single flat block (not a bundle/stack like every
other material icon), matching concrete's own "poured, not stacked" nature.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

CONCRETE_COLOR = (0.7, 0.68, 0.64)
CONCRETE_DARK_COLOR = (0.55, 0.53, 0.5)


def build():
    concrete_mat = flat_material("Concrete", CONCRETE_COLOR)
    dark_mat = flat_material("ConcreteDark", CONCRETE_DARK_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, concrete_mat, (0, 0, 0.05), scale=(0.34, 0.24, 0.05), size=1.0)
    for x, y in [(-0.08, 0.05), (0.1, -0.03), (0.02, 0.08)]:
        part(bpy.ops.mesh.primitive_cube_add, dark_mat, (x, y, 0.101), scale=(0.02, 0.06, 0.001), size=1.0, rotation=(0, 0, 0.3))
