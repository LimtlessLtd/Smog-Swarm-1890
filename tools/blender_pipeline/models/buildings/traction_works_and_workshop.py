"""assets/buildings/traction_works_and_workshop.png — GameEnums.
BuildingType.TRACTION_WORKS_AND_WORKSHOP, Tier 4 Housing & Civil. A
factory hall building the game's own vehicle units — a half-built vehicle
chassis with visible wheels sits outside, distinct from
mechanized_maintenance_depot.py's REPAIR garage by showing NEW
construction (bare frame, no complete body) rather than a whole parked machine.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel, gable_roof  # noqa: E402

WALL_COLOR = (0.42, 0.4, 0.38)
ROOF_COLOR = (0.24, 0.22, 0.2)
FRAME_COLOR = (0.35, 0.32, 0.28)
WHEEL_COLOR = (0.14, 0.13, 0.12)


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    frame_mat = flat_material("Frame", FRAME_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, wall_mat, (-0.1, -0.1, 0.2), scale=(0.44, 0.32, 0.2), size=1.0)
    gable_roof(roof_mat, (-0.1, -0.1, 0.42), width=0.48, depth=0.36, height=0.2, ridge_along_y=False)

    # Bare chassis frame outside — a skeleton, not a finished vehicle body.
    part(bpy.ops.mesh.primitive_cube_add, frame_mat, (0.32, 0.2, 0.14), scale=(0.04, 0.4, 0.05), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, frame_mat, (0.24, 0.2, 0.14), scale=(0.04, 0.4, 0.05), size=1.0)
    for x, y in ((0.28, 0.02), (0.28, 0.38)):
        wheel(wheel_mat, (x, y, 0.06), radius=0.06, thickness=0.06)
