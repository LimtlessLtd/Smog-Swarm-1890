"""assets/icons/energy.png — GameEnums.ResourceType.ENERGY. A lump of coal
beside a lit gas-lamp flame — same subject as the old AI-prompt README,
built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

COAL_COLOR = (0.08, 0.08, 0.09)
FLAME_COLOR = (0.95, 0.6, 0.15)
FLAME_CORE_COLOR = (1.0, 0.85, 0.4)


def build():
    coal_mat = flat_material("Coal", COAL_COLOR)
    flame_mat = flat_material("Flame", FLAME_COLOR)
    core_mat = flat_material("FlameCore", FLAME_CORE_COLOR)

    for x, y, r in [(-0.15, -0.1, 0.14), (-0.05, 0.08, 0.11), (-0.22, 0.08, 0.09)]:
        part(bpy.ops.mesh.primitive_uv_sphere_add, coal_mat, (x, y, r * 0.6), segments=8, ring_count=5, radius=r)

    part(bpy.ops.mesh.primitive_cone_add, flame_mat, (0.22, 0, 0.15), radius1=0.13, radius2=0.01, depth=0.32)
    part(bpy.ops.mesh.primitive_cone_add, core_mat, (0.22, 0.02, 0.1), radius1=0.06, radius2=0.005, depth=0.18)
