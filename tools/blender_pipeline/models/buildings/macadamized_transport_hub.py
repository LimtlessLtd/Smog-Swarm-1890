"""assets/buildings/macadamized_transport_hub.png —
GameEnums.BuildingType.MACADAMIZED_TRANSPORT_HUB, Tier 4.

Re-authored 2026-09-15 for the straight-down camera, and the logistics family's
reference model. The old version was a scatter of grey slabs at 45 degrees that
read as debris rather than a building.

The logistics signature is running track: sleepers and rails crossing the whole
site, with goods sheds set square to them and a turntable at the end of the run.
Track is the one thing that is genuinely more legible from directly above than
from any angle, so this family gained from the change rather than fighting it —
and it is the family where the user's "paths between the buildings" note is the
entire point of the asset rather than a dressing on it.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)

SHED_XY = ((-0.34, -0.30), (0.06, -0.30))
TURNTABLE_XY = (0.44, -0.30)
MAIN_LINE_Y = 0.14


def build():
    gravel_mat, shed_mat, signal_mat = family_materials("logistics")
    sleeper_mat = flat_material("Sleeper", (0.212, 0.196, 0.180))
    ballast_mat = flat_material("Ballast", (0.435, 0.427, 0.435), alpha=0.86)
    yard_mat = flat_material("Yard", (0.388, 0.380, 0.376), alpha=0.82)

    # Ballast under the running lines, and separate yard ground under the sheds.
    ground_patch(ballast_mat, (0.0, MAIN_LINE_Y, 0.002), radius_x=0.66, radius_y=0.22,
                 sides=15, jitter=0.16, seed=301, name="Ballast")
    for i, (sx, sy) in enumerate(SHED_XY):
        ground_patch(yard_mat, (sx, sy, 0.002), radius_x=0.26, radius_y=0.24,
                     sides=11, jitter=0.24, seed=311 + i * 9, name="ShedYard%d" % i)
    ground_patch(yard_mat, (TURNTABLE_XY[0], TURNTABLE_XY[1], 0.002), radius_x=0.24,
                 radius_y=0.24, sides=12, jitter=0.20, seed=331, name="TurntableGround")

    # Sleepers first, then rails on top: the cross-hatch is what makes the lines
    # read as track instead of as three painted stripes.
    for i in range(11):
        part(bpy.ops.mesh.primitive_cube_add, sleeper_mat,
             (-0.58 + i * 0.116, MAIN_LINE_Y, 0.006),
             scale=(0.040, 0.34, 0.008), size=1.0)
    for offset in (-0.12, 0.0, 0.12):
        part(bpy.ops.mesh.primitive_cube_add, signal_mat,
             (0.0, MAIN_LINE_Y + offset, 0.011), scale=(1.22, 0.024, 0.010), size=1.0)

    # Sidings curving off the main line down to each shed and the turntable —
    # these are the paths tying the site together.
    for i, (sx, sy) in enumerate(SHED_XY):
        path(sleeper_mat, [(sx - 0.10, MAIN_LINE_Y - 0.10), (sx, -0.06), (sx, sy + 0.14)],
             width=0.085, seed=41 + i * 7, name="Siding%d" % i)
    path(sleeper_mat, [(0.28, MAIN_LINE_Y - 0.10), (0.42, -0.06), TURNTABLE_XY],
         width=0.085, seed=57, name="TurntableSpur")

    # Goods sheds set square to the track.
    for i, (sx, sy) in enumerate(SHED_XY):
        part(bpy.ops.mesh.primitive_cube_add, gravel_mat, (sx, sy, 0.08),
             scale=(0.30, 0.26, 0.14), size=1.0)
        hip_roof(shed_mat, (sx, sy, 0.15), width=0.28, depth=0.24,
                 height=0.13, ridge_fraction=0.52, name="Shed%d" % i)

    # Turntable: a ring flush with the ground, crossed by a rail. Distinct from
    # the power family's cooling tower because it is flat and crossed, not a
    # raised rim around a dark void.
    part(bpy.ops.mesh.primitive_cylinder_add, sleeper_mat,
         (TURNTABLE_XY[0], TURNTABLE_XY[1], 0.008), radius=0.18, depth=0.012)
    part(bpy.ops.mesh.primitive_cube_add, signal_mat,
         (TURNTABLE_XY[0], TURNTABLE_XY[1], 0.016), scale=(0.34, 0.028, 0.012), size=1.0)

    # Signal post at the yard throat, the logistics equivalent of civic's finial.
    part(bpy.ops.mesh.primitive_cylinder_add, signal_mat, (-0.56, -0.04, 0.10),
         radius=0.038, depth=0.20)
