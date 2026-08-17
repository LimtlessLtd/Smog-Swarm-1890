"""assets/icons/population.png — GameEnums.ResourceType.POPULATION. No
prompt existed for this one (added after the Building tree rework, per
ResourceVisuals.gd's own comment). A simple standing figure silhouette —
the most direct way to represent "population" as a single small icon subject.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

FIGURE_COLOR = (0.4, 0.42, 0.46)
FIGURE_BACK_COLOR = (0.3, 0.32, 0.35)  # A second, smaller figure behind — "population" reads as more than one person.


def build():
    figure_mat = flat_material("Figure", FIGURE_COLOR)
    back_mat = flat_material("FigureBack", FIGURE_BACK_COLOR)

    part(bpy.ops.mesh.primitive_cone_add, back_mat, (-0.14, -0.1, 0.1), radius1=0.13, radius2=0.08, depth=0.2)
    part(bpy.ops.mesh.primitive_uv_sphere_add, back_mat, (-0.14, -0.1, 0.24), segments=9, ring_count=5, radius=0.08)

    part(bpy.ops.mesh.primitive_cone_add, figure_mat, (0.1, 0.1, 0.12), radius1=0.16, radius2=0.1, depth=0.24)
    part(bpy.ops.mesh.primitive_uv_sphere_add, figure_mat, (0.1, 0.1, 0.3), segments=10, ring_count=6, radius=0.1)
