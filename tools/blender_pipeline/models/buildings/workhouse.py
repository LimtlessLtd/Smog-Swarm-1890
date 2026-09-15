"""assets/buildings/workhouse.png — GameEnums.BuildingType.BRICK_HOUSES.

Housing family, but deliberately NOT a terrace: a workhouse is a courtyard block —
four ranges enclosing an exercise yard, which from above is a hard rectangular ring
with a hole in it. terraced_tenement is an open row; this is a closed square. That
contrast is the whole point, since both are brick-red housing.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, yard_plate, roof_vent, ground_patch,
    path, family_materials,
)


def build():
    cobble_mat, roof_mat, chimney_mat = family_materials("housing")
    dirt_mat = flat_material("Dirt", (0.376, 0.353, 0.318), alpha=0.78)
    yard_pave_mat = flat_material("YardPave", (0.478, 0.467, 0.451), alpha=0.92)
    street_mat = flat_material("Street", (0.463, 0.451, 0.435), alpha=0.92)

    ground_patch(dirt_mat, (0.0, 0.0, 0.002), radius_x=0.56, radius_y=0.52,
                 sides=14, jitter=0.20, seed=971, name="Precinct")
    path(street_mat, [(-0.70, -0.44), (0.0, -0.46), (0.70, -0.44)], width=0.13,
         seed=977, name="Street")
    path(street_mat, [(0.0, -0.44), (0.0, -0.36)], width=0.10, seed=979, name="Gate")

    # Exercise yard: paved, enclosed on all four sides.
    yard_plate(yard_pave_mat, location=(0.0, 0.02, 0.004), width=0.42, depth=0.36,
               thickness=0.010)

    # Four ranges. Each is a separate hipped block so Freestyle draws the
    # corners, and the ring reads as built rather than as one thick outline.
    ranges = ((0.0, 0.30, 0.66, 0.20), (0.0, -0.26, 0.66, 0.20),
              (-0.36, 0.02, 0.18, 0.40), (0.36, 0.02, 0.18, 0.40))
    for i, (x, y, w, d) in enumerate(ranges):
        part(bpy.ops.mesh.primitive_cube_add, cobble_mat, (x, y, 0.09),
             scale=(w, d, 0.16), size=1.0)
        hip_roof(roof_mat, (x, y, 0.17), width=w - 0.02, depth=d - 0.02,
                 height=0.13, ridge_fraction=0.72 if w > d else 0.30,
                 name="Range%d" % i)

    # Chimneys along the two long ranges only — a workhouse heats its dormitories.
    for x in (-0.22, 0.0, 0.22):
        for y in (0.30, -0.26):
            roof_vent(chimney_mat, (x, y, 0.29), radius=0.030, height=0.09)
