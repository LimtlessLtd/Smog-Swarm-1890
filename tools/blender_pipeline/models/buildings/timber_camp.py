"""assets/buildings/timber_camp.png — GameEnums.BuildingType.LUMBER_YARD,
Tier 0 Industry & Extraction. A stacked log pile is the whole visual
identity — nothing else in the building roster has a pile of round logs.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof  # noqa: E402

WOOD_COLOR = (0.42, 0.3, 0.18)
LOG_COLOR = (0.35, 0.24, 0.14)
LOG_END_COLOR = (0.58, 0.44, 0.28)
ROOF_COLOR = (0.22, 0.17, 0.12)


def build():
    wood_mat = flat_material("Wood", WOOD_COLOR)
    log_mat = flat_material("Log", LOG_COLOR)
    log_end_mat = flat_material("LogEnd", LOG_END_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)

    # Open-sided shed: 4 posts + a roof, no walls (matches a real timber
    # yard's open-air storage).
    for x in (-0.32, 0.32):
        for y in (-0.22, 0.22):
            part(bpy.ops.mesh.primitive_cylinder_add, wood_mat, (x, y, 0.2), radius=0.045, depth=0.4)
    gable_roof(roof_mat, (0, 0, 0.48), width=0.75, depth=0.55, height=0.25, ridge_along_y=False)

    # Log pile: stacked cylinders, log-end color visible on the front-facing tips.
    for row, count in enumerate([4, 3, 2]):
        z = 0.08 + row * 0.13
        for i in range(count):
            x = (i - (count - 1) / 2.0) * 0.14
            part(bpy.ops.mesh.primitive_cylinder_add, log_mat, (x, 0.5, z),
                 rotation=(1.5708, 0, 0), radius=0.07, depth=0.5)
            part(bpy.ops.mesh.primitive_cylinder_add, log_end_mat, (x, 0.75, z),
                 rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.1), radius=0.07, depth=0.05)
