"""assets/buildings/armory_and_barracks.png — GameEnums.BuildingType.ARMORY_AND_BARRACKS.

Tier 2. garrison's courtyard grown to a square of FOUR ranges around a bigger
parade ground, with a magazine block set apart behind its own traverse. Barrack
count is this family's tier: garrison two ranges, this four, and
high_command_and_cavalry_depot adds the stable lines.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
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
    olive_mat, roof_mat, flag_mat = family_materials("military")
    parade_mat = flat_material("Parade", (0.545, 0.522, 0.416))
    ground_mat = flat_material("Trodden", (0.388, 0.380, 0.294), alpha=0.80)
    track_mat = flat_material("Track", (0.573, 0.553, 0.447), alpha=0.92)

    ground_patch(ground_mat, (-0.02, 0.04, 0.002), radius_x=0.58, radius_y=0.52,
                 sides=15, jitter=0.18, seed=1481, name="Compound")
    ground_patch(ground_mat, (0.40, -0.36, 0.002), radius_x=0.22, radius_y=0.18,
                 sides=10, jitter=0.26, seed=1487, name="MagazineGround")

    yard_plate(parade_mat, location=(-0.02, 0.06, 0.004), width=0.48, depth=0.42,
               thickness=0.012)
    path(track_mat, [(-0.02, -0.20), (0.18, -0.30), (0.38, -0.34)], width=0.09, seed=1489)

    # Four ranges enclosing the parade ground.
    ranges = ((-0.02, 0.36, 0.60, 0.18), (-0.02, -0.24, 0.60, 0.18),
              (-0.36, 0.06, 0.16, 0.38), (0.32, 0.06, 0.16, 0.38))
    for i, (x, y, w, d) in enumerate(ranges):
        part(bpy.ops.mesh.primitive_cube_add, olive_mat, (x, y, 0.08),
             scale=(w, d, 0.14), size=1.0)
        hip_roof(roof_mat, (x, y, 0.15), width=w - 0.02, depth=d - 0.02,
                 height=0.12, ridge_fraction=0.74 if w > d else 0.30,
                 name="Range%d" % i)
        for j in range(3):
            if w > d:
                roof_vent(olive_mat, (x - 0.18 + j * 0.18, y, 0.25), radius=0.026, height=0.08)

    # Magazine: set apart, behind an earth traverse, with the red flag marker.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (0.40, -0.36, 0.08),
         scale=(0.20, 0.17, 0.15), size=1.0)
    hip_roof(roof_mat, (0.40, -0.36, 0.155), width=0.18, depth=0.15,
             height=0.11, ridge_fraction=0.0, name="MagazineCap")
    part(bpy.ops.mesh.primitive_cylinder_add, flag_mat, (0.40, -0.36, 0.28),
         radius=0.048, depth=0.035)
