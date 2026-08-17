"""assets/units/searchlight_tender_<facing>.png — Tier 4 Special,
MOBILE_SUPPLY_DUMP ability. A raised searchlight lamp on a tall armature
is this vehicle's whole silhouette signature — the only Tier 4 unit with
anything rising well above the chassis line (Traction Ram's smokestack is
short; Maxim Quadricycle's gun barrel is horizontal), plus visible supply
crates in the bed for the "mobile supply dump" flavor.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

HULL_COLOR = (0.26, 0.24, 0.22)
WHEEL_COLOR = (0.12, 0.1, 0.08)
CRATE_COLOR = (0.34, 0.26, 0.16)
LAMP_HOUSING_COLOR = (0.18, 0.17, 0.16)
LENS_COLOR = (0.3, 0.03, 0.42)  # Special role accent: deep purple.


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)
    crate_mat = flat_material("Crate", CRATE_COLOR)
    housing_mat = flat_material("Housing", LAMP_HOUSING_COLOR)
    lens_mat = flat_material("Lens", LENS_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, hull_mat,
         (0, 0, 0.3), scale=(0.36, 0.72, 0.22), size=1.0)

    for side in (-0.24, 0.24):
        for forward in (0.26, -0.26):
            wheel(wheel_mat, (side, forward, 0.16), radius=0.16, thickness=0.09)

    # Supply crates stacked in the rear bed — the "mobile supply dump" read.
    part(bpy.ops.mesh.primitive_cube_add, crate_mat,
         (-0.1, -0.28, 0.5), scale=(0.14, 0.14, 0.16), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, crate_mat,
         (0.11, -0.3, 0.46), scale=(0.12, 0.12, 0.12), size=1.0, rotation=(0, 0, 0.2))

    # Searchlight armature: a tall post rising well above the chassis,
    # topped with a wide lamp housing and a large flat lens facing forward
    # — the tallest, most vertically distinct silhouette on the roster.
    part(bpy.ops.mesh.primitive_cylinder_add, housing_mat,
         (0, 0.22, 0.65), radius=0.05, depth=0.6)
    part(bpy.ops.mesh.primitive_cylinder_add, housing_mat,
         (0, 0.22, 0.98), rotation=(1.5708, 0, 0), radius=0.16, depth=0.16)
    part(bpy.ops.mesh.primitive_cylinder_add, lens_mat,
         (0, 0.31, 0.98), rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.3), radius=0.14, depth=0.05)
