"""assets/icons/research.png — GameEnums.ResourceType.RESEARCH_POINTS. An
open notebook and a magnifying glass — same subject as the old AI-prompt
README, built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

PAGE_COLOR = (0.88, 0.84, 0.72)
COVER_COLOR = (0.4, 0.26, 0.16)
BRASS_COLOR = (0.75, 0.6, 0.25)
GLASS_COLOR = (0.6, 0.75, 0.78)


def build():
    page_mat = flat_material("Page", PAGE_COLOR)
    cover_mat = flat_material("Cover", COVER_COLOR)
    brass_mat = flat_material("Brass", BRASS_COLOR)
    glass_mat = flat_material("Glass", GLASS_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, cover_mat, (-0.1, 0, 0.015), scale=(0.34, 0.24, 0.01), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, page_mat, (-0.1, 0, 0.025), scale=(0.3, 0.22, 0.01), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, cover_mat, (-0.1, 0, 0.03), scale=(0.02, 0.24, 0.012), size=1.0)  # Spine.

    part(bpy.ops.mesh.primitive_torus_add, brass_mat, (0.26, 0.1, 0.05), rotation=(0, 0, 0), major_radius=0.11, minor_radius=0.015)
    part(bpy.ops.mesh.primitive_cylinder_add, glass_mat, (0.26, 0.1, 0.05), scale=(1.0, 1.0, 0.1), radius=0.1, depth=0.02)
    part(bpy.ops.mesh.primitive_cylinder_add, brass_mat, (0.4, 0.22, 0.04), rotation=(1.2, 0, 0.6), radius=0.015, depth=0.22)
