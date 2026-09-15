"""assets/buildings/automated_freight_marshalling_yard.png — GameEnums.BuildingType.AUTOMATED_FREIGHT_MARSHALLING_YARD.

Tier 5, and the logistics family's full expression: a fan of SIX sorting sidings
off a single throat, with a hump at the neck and wagon rows standing on the roads.
macadamized_transport_hub is one running line with two sheds and a turntable; this
is the yard that line feeds. A spreading fan of parallel tracks is the most
distinctive ground pattern on the whole roster.

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

SIDING_COUNT = 6


def build():
    gravel_mat, shed_mat, signal_mat = family_materials("logistics")
    sleeper_mat = flat_material("Sleeper", (0.212, 0.196, 0.180))
    ballast_mat = flat_material("Ballast", (0.435, 0.427, 0.435), alpha=0.86)
    wagon_mat = flat_material("Wagon", (0.376, 0.298, 0.243))

    ground_patch(ballast_mat, (0.06, 0.0, 0.002), radius_x=0.62, radius_y=0.44,
                 sides=16, jitter=0.14, seed=1571, name="YardBallast")

    # Sorting fan: every siding leaves the same throat and spreads.
    for i in range(SIDING_COUNT):
        spread = (i - (SIDING_COUNT - 1) / 2.0) * 0.115
        path(sleeper_mat,
             [(-0.60, 0.0), (-0.34, spread * 0.35), (0.04, spread * 0.85), (0.62, spread)],
             width=0.060, jitter=0.10, seed=1581 + i * 3, name="Siding%d" % i)

    # Hump at the throat — the thing that makes it a marshalling yard.
    part(bpy.ops.mesh.primitive_cube_add, gravel_mat, (-0.50, 0.0, 0.035),
         scale=(0.16, 0.22, 0.05), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, signal_mat, (-0.50, 0.0, 0.065),
         scale=(0.18, 0.030, 0.014), size=1.0)

    # Wagons standing on three of the roads.
    for row, i in enumerate((1, 3, 4)):
        spread = (i - (SIDING_COUNT - 1) / 2.0) * 0.115
        for col in range(3):
            part(bpy.ops.mesh.primitive_cube_add, wagon_mat,
                 (0.10 + col * 0.15, spread * 0.92, 0.045),
                 scale=(0.115, 0.070, 0.055), size=1.0)

    # Control cabin overlooking the fan, and the yard signal.
    part(bpy.ops.mesh.primitive_cube_add, gravel_mat, (-0.30, -0.40, 0.08),
         scale=(0.22, 0.18, 0.15), size=1.0)
    hip_roof(shed_mat, (-0.30, -0.40, 0.155), width=0.20, depth=0.16,
             height=0.11, ridge_fraction=0.45)
    part(bpy.ops.mesh.primitive_cylinder_add, signal_mat, (-0.58, -0.28, 0.10),
         radius=0.036, depth=0.20)
