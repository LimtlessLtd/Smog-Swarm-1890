"""assets/units/chasseur_<facing>.png — Tier 2 Special, MOUNTED_FIREARM
ability. "Now mounted and carries a real handgun (previously just a sabre,
no mount)" (todo.md's own Phase 5.4 note) — genuinely armed unlike Tier 0's
unarmed-scout Outrider, which this model distinguishes with a darker horse,
a plumed cap, and a visible pistol in the rider's hand instead of an empty
raised arm.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash, curved_part  # noqa: E402

HORSE_COLOR = (0.15, 0.13, 0.12)      # Near-black horse — distinct from Outrider's tan mount.
HORSE_DARK_COLOR = (0.08, 0.07, 0.06)
COAT_COLOR = (0.2, 0.19, 0.22)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.14, 0.13, 0.14)
PLUME_COLOR = (0.85, 0.82, 0.75)      # Cream plume — neutral, echoes redcoat.py/rifleman.py's cross-belt color for uniform-family consistency.
PISTOL_COLOR = (0.3, 0.03, 0.42)      # Special role accent: deep purple.


def build():
    horse_mat = flat_material("Horse", HORSE_COLOR)
    horse_dark_mat = flat_material("HorseDark", HORSE_DARK_COLOR)
    coat_mat = flat_material("Coat", COAT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    plume_mat = flat_material("Plume", PLUME_COLOR)
    pistol_mat = flat_material("Pistol", PISTOL_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0, 0.55), rotation=(1.5708, 0, 0), radius=0.22, depth=0.75)
    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0.45, 0.75), rotation=(-0.9, 0, 0), radius=0.12, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, horse_mat,
         (0, 0.62, 1.0), segments=8, ring_count=5, radius=0.13)

    for side in (-0.14, 0.14):
        for forward in (0.28, -0.28):
            part(bpy.ops.mesh.primitive_cylinder_add, horse_dark_mat,
                 (side, forward, 0.25), radius=0.06, depth=0.5)

    part(bpy.ops.mesh.primitive_cone_add, horse_dark_mat,
         (0, -0.42, 0.45), rotation=(0.4, 0, 0), radius1=0.08, radius2=0.02, depth=0.35)

    saddle_mat = flat_material("Saddle", (0.22, 0.15, 0.1))
    part(bpy.ops.mesh.primitive_cube_add, saddle_mat,
         (0, -0.1, 0.78), scale=(0.16, 0.35, 0.06), size=1.0)
    curved_part(saddle_mat, (0, 0.15, 0.95), (1.5708, 0, 0),
                points=[(-0.35, 0, 0), (-0.15, 0, -0.1), (0.05, 0, -0.05)], bevel_depth=0.012)

    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0, -0.1, 1.0), radius=0.2, depth=0.4)
    sash(pistol_mat, (0, -0.1, 1.0), 0.2)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, -0.1, 1.28), segments=10, ring_count=6, radius=0.16)

    # Plumed cap: a short cap topped with a cream plume spike — a taller,
    # more decorated silhouette than Outrider's plain cap, distinct from
    # the infantry shako/forage-cap family too (a spike, not a brim/peak).
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, -0.13, 1.4), scale=(1.0, 1.0, 0.5), radius=0.17, depth=0.14)
    part(bpy.ops.mesh.primitive_cone_add, plume_mat,
         (0, -0.13, 1.56), radius1=0.04, radius2=0.005, depth=0.22)

    # Pistol: gripped in the raised hand, visibly a weapon (unlike
    # Outrider's empty raised hand) — small enough to read as a handgun,
    # not a rifle, keeping the silhouette distinction from the ranged units.
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.08, 0.18, 0.9), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_cube_add, pistol_mat,
         (0.12, 0.24, 0.94), scale=(0.03, 0.1, 0.05), size=1.0, rotation=(0, 0, -0.2))

    part(bpy.ops.mesh.primitive_cube_add, saddle_mat,
         (0.3, 0.0, 0.92), scale=(0.1, 0.16, 0.14), size=1.0, rotation=(0, 0, 0.3))  # Holster, neutral leather — the pistol itself already carries the accent.
