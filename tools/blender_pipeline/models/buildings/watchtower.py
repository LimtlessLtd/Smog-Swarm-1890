"""assets/buildings/watchtower.png — GameEnums.BuildingType.WATCHTOWER.

Tier 0, and the SMALLEST building on the roster — it should read as a single
object, not a site. One square tower with a pyramid cap and a railed platform,
standing on a scrap of trodden ground with a footpath to it. Its whole job is to
be identifiable at map zoom as "one small tower", which is why there is nothing
else in the frame.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)


def build():
    olive_mat, roof_mat, flag_mat = family_materials("military")
    ground_mat = flat_material("Trodden", (0.388, 0.380, 0.294), alpha=0.80)
    track_mat = flat_material("Track", (0.573, 0.553, 0.447), alpha=0.92)
    timber_mat = flat_material("Timber", (0.435, 0.361, 0.243))

    ground_patch(ground_mat, (0.0, 0.0, 0.002), radius_x=0.30, radius_y=0.28,
                 sides=11, jitter=0.26, seed=1521, name="Ground")
    path(track_mat, [(-0.46, -0.30), (-0.20, -0.16), (-0.02, -0.06)],
         width=0.07, seed=1523)

    # Four legs splayed to the corners, so the tower reads as a frame from above.
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part(bpy.ops.mesh.primitive_cube_add, timber_mat, (dx * 0.15, dy * 0.15, 0.14),
             scale=(0.045, 0.045, 0.28), size=1.0)
    # Platform with a railing, then the pyramid cap.
    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (0.0, 0.0, 0.29),
         scale=(0.42, 0.42, 0.03), size=1.0)
    for dx, dy, sx, sy in ((0.0, 0.20, 0.42, 0.030), (0.0, -0.20, 0.42, 0.030),
                           (0.20, 0.0, 0.030, 0.42), (-0.20, 0.0, 0.030, 0.42)):
        part(bpy.ops.mesh.primitive_cube_add, timber_mat, (dx, dy, 0.325),
             scale=(sx, sy, 0.05), size=1.0)
    hip_roof(roof_mat, (0.0, 0.0, 0.35), width=0.40, depth=0.40,
             height=0.24, ridge_fraction=0.0, name="Cap")
    part(bpy.ops.mesh.primitive_cylinder_add, flag_mat, (0.0, 0.0, 0.60),
         radius=0.040, depth=0.03)
