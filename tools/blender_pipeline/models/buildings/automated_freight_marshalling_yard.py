"""assets/buildings/automated_freight_marshalling_yard.png — GameEnums.
BuildingType.AUTOMATED_FREIGHT_MARSHALLING_YARD, Tier 5 Industry &
Extraction. Parallel rail tracks with freight wagons — the only building
with visible rails/sleepers, distinct from macadamized_transport_hub.py's
paved road X-junction by being a straight rail yard, not a road crossing.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

BALLAST_COLOR = (0.4, 0.38, 0.36)
RAIL_COLOR = (0.55, 0.53, 0.5)
SLEEPER_COLOR = (0.28, 0.22, 0.16)
WAGON_COLOR = (0.45, 0.24, 0.16)
WHEEL_COLOR = (0.14, 0.13, 0.12)


def build():
    ballast_mat = flat_material("Ballast", BALLAST_COLOR)
    rail_mat = flat_material("Rail", RAIL_COLOR)
    sleeper_mat = flat_material("Sleeper", SLEEPER_COLOR)
    wagon_mat = flat_material("Wagon", WAGON_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, ballast_mat, (0, 0, 0.005), scale=(0.75, 0.5, 0.01), size=1.0)

    for track_y in (-0.15, 0.15):
        for i in range(6):
            t = (i / 5.0) - 0.5
            part(bpy.ops.mesh.primitive_cube_add, sleeper_mat, (t * 0.65, track_y, 0.015), scale=(0.05, 0.12, 0.01), size=1.0)
        for rail_offset in (-0.05, 0.05):
            part(bpy.ops.mesh.primitive_cube_add, rail_mat, (0, track_y + rail_offset, 0.02), scale=(0.7, 0.01, 0.01), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, wagon_mat, (0.15, -0.15, 0.09), scale=(0.24, 0.13, 0.07), size=1.0)
    for x in (0.06, 0.24):
        wheel(wheel_mat, (x, -0.15, 0.04), radius=0.045, thickness=0.03)
