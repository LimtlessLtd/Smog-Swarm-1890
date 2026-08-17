"""assets/units/yeoman_marksman_<facing>.png — Tier 1 Ranged. "First
firearm-era ranged unit" (UnitCatalog.gd comment) — a straight rifle
replaces Toxophilite's bow, and a wide-brimmed slouch hat replaces its
hood, so the two Ranged units read as clearly different despite sharing
the deep-blue role accent.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.24, 0.3, 0.2)   # Muted hunting green — distinct hue from every earlier unit's coat.
BOOT_COLOR = (0.16, 0.13, 0.1)
BELT_COLOR = (0.3, 0.2, 0.13)
SKIN_COLOR = (0.72, 0.56, 0.46)
HAT_COLOR = (0.18, 0.16, 0.12)
RIFLE_COLOR = (0.05, 0.1, 0.45)  # Ranged role accent: deep blue.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    hat_mat = flat_material("Hat", HAT_COLOR)
    rifle_mat = flat_material("Rifle", RIFLE_COLOR)
    wood_mat = flat_material("Stock", (0.3, 0.2, 0.12))

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.32, radius2=0.26, depth=0.6)
    sash(rifle_mat, (0, 0, 1.05), 0.3)

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.12), radius=0.32, depth=1.0)

    # Arms: both raised, aiming the rifle forward.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.28, 0.28, 1.1), rotation=(1.2, 0, -0.1), radius=0.08, depth=0.45)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.28, 0.05, 1.05), rotation=(0.5, 0, 0.4), radius=0.08, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.4, 0.42, 1.15), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.38, -0.05, 1.02), segments=8, ring_count=5, radius=0.07)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.55), segments=10, ring_count=6, radius=0.2)

    # Slouch hat: a wide flat brim disc under a shallow dome — a
    # completely different silhouette from Navvy's flat cap or any Tier 0
    # headwear, reads unmistakably as "wide hat" even at small size.
    part(bpy.ops.mesh.primitive_cylinder_add, hat_mat,
         (0, 0, 1.66), scale=(1.0, 1.0, 0.15), radius=0.32, depth=0.1)
    part(bpy.ops.mesh.primitive_uv_sphere_add, hat_mat,
         (0, 0, 1.72), scale=(1.0, 1.0, 0.55), segments=8, ring_count=5, radius=0.18)

    # Rifle: a long straight barrel (unlike Toxophilite's curved bow),
    # angled diagonally across the whole figure — the longest single
    # silhouette element on the roster so far.
    part(bpy.ops.mesh.primitive_cylinder_add, rifle_mat,
         (0.05, 0.5, 1.15), rotation=(1.3, 0, -0.2), radius=0.035, depth=0.85)
    part(bpy.ops.mesh.primitive_cube_add, wood_mat,
         (0.3, -0.05, 1.0), scale=(0.05, 0.14, 0.07), size=1.0, rotation=(1.3, 0, -0.2))
