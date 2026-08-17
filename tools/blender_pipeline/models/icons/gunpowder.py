"""assets/icons/gunpowder.png — GameEnums.ResourceType.GUNPOWDER. A cloth
powder pouch with loose black grains beside it — same subject as the old
AI-prompt README, built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

POUCH_COLOR = (0.32, 0.3, 0.26)
DRAWSTRING_COLOR = (0.5, 0.08, 0.08)
GRAIN_COLOR = (0.1, 0.1, 0.1)


def build():
    pouch_mat = flat_material("Pouch", POUCH_COLOR)
    string_mat = flat_material("String", DRAWSTRING_COLOR)
    grain_mat = flat_material("Grain", GRAIN_COLOR)

    part(bpy.ops.mesh.primitive_uv_sphere_add, pouch_mat, (0, 0, 0.13), scale=(1.0, 1.0, 1.15), segments=10, ring_count=6, radius=0.2)
    part(bpy.ops.mesh.primitive_cylinder_add, pouch_mat, (0, 0, 0.28), scale=(0.5, 0.5, 0.3), radius=0.14, depth=0.1)
    part(bpy.ops.mesh.primitive_torus_add, string_mat, (0, 0, 0.24), major_radius=0.11, minor_radius=0.012)

    for x, y in [(0.24, 0.1), (0.28, -0.05), (0.22, -0.15)]:
        part(bpy.ops.mesh.primitive_uv_sphere_add, grain_mat, (x, y, 0.03), segments=6, ring_count=4, radius=0.025)
