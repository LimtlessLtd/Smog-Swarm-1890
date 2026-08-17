"""assets/units/maxim_quadricycle_<facing>.png — Tier 4 Ranged,
requires_gunpowder. An open-framework 4-wheeled runabout with a pivot-
mounted Maxim gun, distinct from Traction Ram's closed armored hull by
being visibly open/skeletal (a seat and gun exposed on a bare chassis
rail, not a solid box) — the silhouette difference alone separates the
two Tier 4 units before color does.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

FRAME_COLOR = (0.24, 0.22, 0.18)
WHEEL_COLOR = (0.12, 0.1, 0.08)
SEAT_COLOR = (0.2, 0.14, 0.1)
GUN_COLOR = (0.05, 0.1, 0.45)  # Ranged role accent: deep blue.


def build():
    frame_mat = flat_material("Frame", FRAME_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)
    seat_mat = flat_material("Seat", SEAT_COLOR)
    gun_mat = flat_material("Gun", GUN_COLOR)

    # Chassis rail: a thin, low frame — much slimmer than Traction Ram's
    # solid hull, reads as "open vehicle" immediately.
    part(bpy.ops.mesh.primitive_cube_add, frame_mat,
         (0, 0, 0.24), scale=(0.32, 0.7, 0.1), size=1.0)

    for side in (-0.22, 0.22):
        for forward in (0.26, -0.26):
            wheel(wheel_mat, (side, forward, 0.16), radius=0.16, thickness=0.08)

    part(bpy.ops.mesh.primitive_cube_add, seat_mat,
         (0, -0.15, 0.36), scale=(0.22, 0.18, 0.1), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, seat_mat,
         (0, -0.24, 0.5), scale=(0.2, 0.04, 0.14), size=1.0)  # Seat back.

    # Gun mount: a pivot post rising from the chassis, with the Maxim gun's
    # long barrel projecting forward and slightly up — the barrel is the
    # single longest, thinnest element on the vehicle, easy to read as "gun."
    part(bpy.ops.mesh.primitive_cylinder_add, frame_mat,
         (0, 0.15, 0.42), radius=0.05, depth=0.2)
    part(bpy.ops.mesh.primitive_cylinder_add, gun_mat,
         (0, 0.15, 0.5), scale=(1.0, 1.0, 1.0), radius=0.09, depth=0.16)  # Gun receiver block.
    part(bpy.ops.mesh.primitive_cylinder_add, gun_mat,
         (0, 0.45, 0.53), rotation=(1.5708, 0, 0), radius=0.03, depth=0.55)  # Barrel.
    part(bpy.ops.mesh.primitive_cylinder_add, frame_mat,
         (0, 0.15, 0.56), rotation=(0.3, 0, 0), radius=0.015, depth=0.3)  # Traverse handle.

    # Ammo box beside the seat.
    part(bpy.ops.mesh.primitive_cube_add, gun_mat,
         (0.16, -0.05, 0.34), scale=(0.08, 0.1, 0.08), size=1.0)
