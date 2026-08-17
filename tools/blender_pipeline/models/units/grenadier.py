"""assets/units/grenadier_<facing>.png — Tier 1 Special, EXPLOSIVE_SPLASH
ability. A bandolier of grenade-shaped pouches doubles as this unit's
deep-purple role accent (instead of a sash riding separately from the
weapon, like Truncheoneer/Toxophilite) — the accent IS the payload here,
which reads more truthfully for an explosives specialist. Distinct from
Tier 0's Outrider (mounted, unarmed) by being on foot and visibly armed.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

COAT_COLOR = (0.16, 0.18, 0.24)   # Dark navy tunic — distinct hue from every earlier unit's coat.
BOOT_COLOR = (0.1, 0.09, 0.08)
BELT_COLOR = (0.28, 0.19, 0.12)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.12, 0.12, 0.16)
GRENADE_COLOR = (0.3, 0.03, 0.42)  # Special role accent: deep purple.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    grenade_mat = flat_material("Grenade", GRENADE_COLOR)

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.33, radius2=0.27, depth=0.6)

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.12), radius=0.32, depth=1.0)

    # Bandolier: a diagonal strap of small round grenade pouches across the
    # chest — bigger, bolder, and more numerous than a thin sash stripe, and
    # a silhouette no other unit has (a row of bumps, not a flat band).
    for i in range(4):
        t = i / 3.0
        part(bpy.ops.mesh.primitive_uv_sphere_add, grenade_mat,
             (-0.24 + t * 0.5, 0.26 - t * 0.06, 1.28 - t * 0.42),
             segments=8, ring_count=5, radius=0.075)

    # Arms: one holding a grenade forward-low (about to throw), one at rest.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.3, 0.0, 1.0), rotation=(0.15, 0, 0.1), radius=0.08, depth=0.55)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.28, 0.25, 0.95), rotation=(1.0, 0, -0.3), radius=0.08, depth=0.45)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.32, -0.02, 0.7), segments=8, ring_count=5, radius=0.08)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.42, 0.4, 0.85), segments=8, ring_count=5, radius=0.08)
    part(bpy.ops.mesh.primitive_uv_sphere_add, grenade_mat,
         (0.42, 0.4, 0.85), segments=8, ring_count=5, radius=0.09)  # The grenade itself, gripped in the raised hand.

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.5), segments=10, ring_count=6, radius=0.2)

    # Pillbox cap: a tall narrow cylinder — taller and narrower than any
    # earlier headwear, reads as a distinct silhouette from directly overhead.
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, 0, 1.68), radius=0.19, depth=0.16)
