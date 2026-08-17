"""assets/units/field_howitzer_gun_tractor_<facing>.png — Tier 5 Ranged,
requires_gunpowder, second-heaviest training_cost after Holt Breaker. A
thick howitzer barrel raised at a real artillery elevation angle (unlike
Maxim Quadricycle's horizontal machine-gun barrel) plus a wide gun shield
— the shield and the barrel's steep angle are this unit's whole silhouette
signature, unmistakable from any other vehicle even in outline.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

HULL_COLOR = (0.26, 0.24, 0.22)
WHEEL_COLOR = (0.12, 0.1, 0.08)
SHIELD_COLOR = (0.22, 0.21, 0.2)
BARREL_COLOR = (0.05, 0.1, 0.45)  # Ranged role accent: deep blue.


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    wheel_mat = flat_material("Wheel", WHEEL_COLOR)
    shield_mat = flat_material("Shield", SHIELD_COLOR)
    barrel_mat = flat_material("Barrel", BARREL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, hull_mat,
         (0, -0.15, 0.32), scale=(0.4, 0.55, 0.24), size=1.0)

    # Large-diameter wheels — a towed-gun-carriage look, bigger relative to
    # the hull than any Tier 4 vehicle's wheels.
    for side in (-0.26, 0.26):
        wheel(wheel_mat, (side, -0.1, 0.22), radius=0.22, thickness=0.1)

    # Gun shield: a wide flat plate ahead of the mount — a large flat
    # silhouette element unique to this unit, reading as "artillery" even
    # before the barrel is visible.
    part(bpy.ops.mesh.primitive_cube_add, shield_mat,
         (0, 0.22, 0.55), scale=(0.42, 0.04, 0.32), size=1.0, rotation=(0.1, 0, 0))

    # Howitzer barrel: thick, mounted on a pivot, elevated at a real
    # artillery angle rather than level — the steep angle alone
    # distinguishes it from Maxim Quadricycle's horizontal gun.
    part(bpy.ops.mesh.primitive_cylinder_add, hull_mat,
         (0, 0.05, 0.55), radius=0.13, depth=0.2)
    part(bpy.ops.mesh.primitive_cylinder_add, barrel_mat,
         (0, 0.35, 0.72), rotation=(1.0, 0, 0), radius=0.055, depth=0.75)
    part(bpy.ops.mesh.primitive_cylinder_add, barrel_mat,
         (0, 0.62, 0.98), rotation=(1.0, 0, 0), scale=(1.3, 1.3, 1.0), radius=0.065, depth=0.1)  # Muzzle bulge.
