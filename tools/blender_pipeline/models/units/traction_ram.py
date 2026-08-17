"""assets/units/traction_ram_<facing>.png — Tier 4 Melee, TRAMPLE_KNOCKBACK
ability. First vehicle on the roster — a completely different body plan
from every Tier 0-3 infantry/cavalry unit (boxy chassis + wheels, no
biped/quadruped silhouette at all), matching Style DNA's "Tier 4-5 are
heavy steam-powered engineering vehicles" note. A wide plow-blade ram at
the front is this unit's whole visual identity — nothing else on the
roster has a flat wedge silhouette.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

HULL_COLOR = (0.28, 0.26, 0.24)
PLATE_COLOR = (0.2, 0.19, 0.18)
WHEEL_COLOR = (0.1, 0.09, 0.08)
STACK_COLOR = (0.16, 0.15, 0.15)
RAM_COLOR = (0.5, 0.03, 0.05)  # Melee role accent: deep red.


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    plate_mat = flat_material("Plate", PLATE_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)
    stack_mat = flat_material("Stack", STACK_COLOR)
    ram_mat = flat_material("Ram", RAM_COLOR)

    # Chassis: a long low box, riveted-plate look via a second, slightly
    # narrower box on top instead of a single flat slab.
    part(bpy.ops.mesh.primitive_cube_add, hull_mat,
         (0, -0.05, 0.32), scale=(0.42, 0.75, 0.24), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, plate_mat,
         (0, -0.05, 0.5), scale=(0.36, 0.65, 0.1), size=1.0)

    # Ram blade: a wide wedge at the front (+Y), angled so its face reads
    # clearly as a flat plow even from an overhead angle — the widest
    # single element on the roster relative to the body it's attached to.
    part(bpy.ops.mesh.primitive_cube_add, ram_mat,
         (0, 0.42, 0.35), scale=(0.5, 0.06, 0.3), size=1.0, rotation=(0.15, 0, 0))
    part(bpy.ops.mesh.primitive_cube_add, ram_mat,
         (0, 0.35, 0.15), scale=(0.55, 0.1, 0.06), size=1.0)  # Lower skirt blade, closer to the ground.

    # Smokestack, offset toward the rear.
    part(bpy.ops.mesh.primitive_cylinder_add, stack_mat,
         (-0.12, -0.3, 0.7), radius=0.07, depth=0.4)
    part(bpy.ops.mesh.primitive_cylinder_add, stack_mat,
         (-0.12, -0.3, 0.92), scale=(1.2, 1.2, 0.3), radius=0.09, depth=0.08)  # Stack cap, slightly wider.

    for side in (-0.24, 0.24):
        for forward in (0.28, -0.28):
            wheel(wheel_mat, (side, forward, 0.16), radius=0.16, thickness=0.1)

    # Rivets: small cube bumps along the hull's top edge — a cheap, quick
    # "riveted plate" read without modeling real seams.
    for i in range(5):
        t = (i / 4.0) - 0.5
        part(bpy.ops.mesh.primitive_cube_add, plate_mat,
             (0.19, t * 0.6 - 0.05, 0.44), scale=(0.02, 0.02, 0.02), size=1.0)
