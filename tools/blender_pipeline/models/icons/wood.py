"""assets/icons/wood.png — GameEnums.ResourceType.WOOD. A bundle of
rough-cut timber logs, tied together — same subject as the old AI-prompt
README, built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

LOG_COLOR = (0.5, 0.34, 0.18)
LOG_END_COLOR = (0.72, 0.55, 0.34)
ROPE_COLOR = (0.3, 0.24, 0.14)


def build():
    log_mat = flat_material("Log", LOG_COLOR)
    end_mat = flat_material("LogEnd", LOG_END_COLOR)
    rope_mat = flat_material("Rope", ROPE_COLOR)

    # Logs run along Y (their own length axis); (x, z) offsets stack them
    # into a bundle cross-section perpendicular to that length.
    positions = [(-0.14, 0.08), (0.14, 0.08), (0.0, 0.08), (-0.07, 0.2), (0.07, 0.2)]
    for x, z in positions:
        part(bpy.ops.mesh.primitive_cylinder_add, log_mat, (x, 0.0, z),
             rotation=(1.5708, 0, 0), radius=0.09, depth=0.42)
        part(bpy.ops.mesh.primitive_cylinder_add, end_mat, (x, 0.21, z),
             rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.08), radius=0.09, depth=0.04)

    part(bpy.ops.mesh.primitive_torus_add, rope_mat, (0, -0.05, 0.14),
         rotation=(0, 1.5708, 0), major_radius=0.2, minor_radius=0.015)
