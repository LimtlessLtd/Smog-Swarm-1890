"""assets/buildings/macadamized_transport_hub.png — GameEnums.BuildingType.
MACADAMIZED_TRANSPORT_HUB, Tier 4 Industry & Extraction. A paved road
junction (a flat grey X-shaped intersection) with a signpost — the only
building that's mostly a flat paved surface rather than a raised
structure, reading as infrastructure, not a factory.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

ROAD_COLOR = (0.42, 0.42, 0.42)
LINE_COLOR = (0.952, 0.867, 0.526)
POST_COLOR = (0.336, 0.269, 0.168)


def build():
    road_mat = flat_material("Road", ROAD_COLOR)
    line_mat = flat_material("Line", LINE_COLOR)
    post_mat = flat_material("Post", POST_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, road_mat, (0, 0, 0.01), scale=(0.6, 0.22, 0.02), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, road_mat, (0, 0, 0.01), scale=(0.22, 0.6, 0.02), size=1.0, rotation=(0, 0, 0))

    for i in range(6):
        t = (i / 5.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, line_mat, (t * 0.55, 0, 0.025), scale=(0.04, 0.015, 0.005), size=1.0)

    part(bpy.ops.mesh.primitive_cylinder_add, post_mat, (0.3, 0.3, 0.15), radius=0.02, depth=0.3)
    part(bpy.ops.mesh.primitive_cube_add, post_mat, (0.34, 0.3, 0.26), scale=(0.08, 0.02, 0.03), size=1.0)
