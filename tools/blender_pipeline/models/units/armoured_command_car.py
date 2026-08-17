"""assets/units/armoured_command_car_<facing>.png — Tier 5 Special,
RAPID_RESPONSE ability. A fully enclosed rounded armored hull (unlike
Searchlight Tender's open flatbed) topped with a tall radio antenna — the
enclosed-hull-plus-antenna silhouette is unique among every vehicle on the
roster, reading as "command vehicle" rather than "workhorse."
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

HULL_COLOR = (0.22, 0.21, 0.22)
TURRET_COLOR = (0.18, 0.17, 0.19)
WHEEL_COLOR = (0.1, 0.09, 0.08)
ANTENNA_COLOR = (0.3, 0.03, 0.42)  # Special role accent: deep purple.


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    turret_mat = flat_material("Turret", TURRET_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)
    antenna_mat = flat_material("Antenna", ANTENNA_COLOR)

    # Enclosed hull: a rounded-top box (cylinder-capped) — the only vehicle
    # on the roster with a curved roof instead of a flat or open deck.
    part(bpy.ops.mesh.primitive_cube_add, hull_mat,
         (0, 0, 0.34), scale=(0.4, 0.75, 0.26), size=1.0)
    part(bpy.ops.mesh.primitive_cylinder_add, hull_mat,
         (0, 0, 0.58), rotation=(0, 1.5708, 0), scale=(1.0, 1.0, 1.0), radius=0.2, depth=0.7)

    # Small raised turret/hatch on top, off-center toward the front.
    part(bpy.ops.mesh.primitive_cylinder_add, turret_mat,
         (0, 0.15, 0.78), radius=0.14, depth=0.16)

    for side in (-0.24, 0.24):
        for forward in (0.26, -0.26):
            wheel(wheel_mat, (side, forward, 0.16), radius=0.17, thickness=0.09)

    # Hull trim stripe: a wide flat band along the hull's side — measured
    # directly on a real render that a thin antenna ALONE reads as almost
    # solid black (a 0.015-radius cylinder is thinner than the Freestyle
    # outline stroke itself at this render resolution, so the fill color
    # underneath barely survives). This is the accent's real, reliably
    # visible carrier; the antenna is a secondary flourish, not the sole
    # accent surface the way it was in the first pass.
    part(bpy.ops.mesh.primitive_cube_add, antenna_mat,
         (0.2, 0, 0.36), scale=(0.02, 0.7, 0.1), size=1.0)

    # Radio antenna: a tall whip rising well above the hull — thickened
    # from the first pass's 0.015 radius (which the outline swallowed
    # almost entirely) to comfortably clear that threshold.
    part(bpy.ops.mesh.primitive_cylinder_add, antenna_mat,
         (-0.05, -0.2, 1.05), rotation=(0.15, 0.05, 0), radius=0.04, depth=0.55)
    part(bpy.ops.mesh.primitive_uv_sphere_add, antenna_mat,
         (-0.09, -0.35, 1.3), segments=6, ring_count=4, radius=0.055)  # Antenna tip bead.
