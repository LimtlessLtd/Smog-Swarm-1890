"""assets/units/holt_breaker_<facing>.png — Tier 5 Melee, TRAMPLE_KNOCKBACK
ability, the roster's heaviest unit (fuel_reserve 50 Coal, largest
training_cost). Continuous tracks instead of Traction Ram's 4 round
wheels — "Holt" references the real Holt Manufacturing Company's tracked
tractors, the actual mechanical ancestor of the tank — plus a bigger,
double-tier ram blade so it reads as a heavier escalation of the same
Melee-vehicle idea, not a recolor.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

HULL_COLOR = (0.24, 0.22, 0.2)
PLATE_COLOR = (0.16, 0.15, 0.14)
TRACK_COLOR = (0.08, 0.07, 0.06)
STACK_COLOR = (0.14, 0.13, 0.13)
RAM_COLOR = (0.5, 0.03, 0.05)  # Melee role accent: deep red.


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    plate_mat = flat_material("Plate", PLATE_COLOR)
    track_mat = flat_material("Track", TRACK_COLOR)
    stack_mat = flat_material("Stack", STACK_COLOR)
    ram_mat = flat_material("Ram", RAM_COLOR)

    # Hull: taller and wider than Traction Ram's, a genuinely bigger machine.
    part(bpy.ops.mesh.primitive_cube_add, hull_mat,
         (0, -0.05, 0.4), scale=(0.46, 0.8, 0.3), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, plate_mat,
         (0, -0.1, 0.62), scale=(0.38, 0.55, 0.1), size=1.0)

    # Tracks: long flattened boxes running the hull's full length on both
    # sides, replacing wheels entirely — the single biggest silhouette
    # difference from every wheeled Tier 4 vehicle.
    for side in (-0.28, 0.28):
        part(bpy.ops.mesh.primitive_cube_add, track_mat,
             (side, -0.05, 0.14), scale=(0.09, 0.85, 0.16), size=1.0)
        # Track links: small ridges along the track's length for a
        # readable tread pattern at close zoom.
        for i in range(6):
            t = (i / 5.0) - 0.5
            part(bpy.ops.mesh.primitive_cube_add, track_mat,
                 (side, -0.05 + t * 0.75, 0.24), scale=(0.1, 0.02, 0.02), size=1.0)

    # Double-tier ram blade — bigger than Traction Ram's single blade,
    # stacked upper+lower plates for a visibly heavier ramming face.
    part(bpy.ops.mesh.primitive_cube_add, ram_mat,
         (0, 0.46, 0.5), scale=(0.55, 0.06, 0.32), size=1.0, rotation=(0.12, 0, 0))
    part(bpy.ops.mesh.primitive_cube_add, ram_mat,
         (0, 0.42, 0.2), scale=(0.6, 0.09, 0.18), size=1.0, rotation=(0.08, 0, 0))

    part(bpy.ops.mesh.primitive_cylinder_add, stack_mat,
         (-0.14, -0.35, 0.85), radius=0.08, depth=0.45)
    part(bpy.ops.mesh.primitive_cylinder_add, stack_mat,
         (-0.14, -0.35, 1.1), scale=(1.2, 1.2, 0.3), radius=0.1, depth=0.08)
