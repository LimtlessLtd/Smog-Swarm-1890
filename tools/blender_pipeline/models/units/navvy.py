"""assets/units/navvy_<facing>.png — Tier 1 Melee. "Navvy": Victorian
railway/canal construction laborer, not a soldier — silhouette leans
working-class (flat cap, pickaxe) rather than military, distinct from
Tier 0's Truncheoneer (custodian helmet, truncheon) even though both are
Melee/red.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.4, 0.34, 0.22)   # Khaki work jacket — distinct hue from every Tier 0 coat color.
BOOT_COLOR = (0.16, 0.13, 0.1)
BELT_COLOR = (0.3, 0.2, 0.13)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.2, 0.18, 0.14)
PICKAXE_COLOR = (0.5, 0.03, 0.05)  # Melee role accent: deep red.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    pickaxe_mat = flat_material("Pickaxe", PICKAXE_COLOR)
    wood_mat = flat_material("Handle", (0.35, 0.24, 0.14))

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0, 0, 1.05), radius=0.3, depth=0.6)  # Straight cylinder, not tapered — a work jacket, not a tailored military coat.
    sash(pickaxe_mat, (0, 0, 1.05), 0.3)

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.12), radius=0.32, depth=1.0)

    # Arms: both lower, one gripping the pickaxe haft mid-shaft.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.3, 0.05, 1.0), rotation=(0.2, 0, 0.15), radius=0.08, depth=0.5)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.3, 0.15, 1.02), rotation=(0.6, 0, -0.3), radius=0.08, depth=0.5)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.32, 0.02, 0.76), segments=8, ring_count=5, radius=0.08)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.4, 0.28, 0.82), segments=8, ring_count=5, radius=0.08)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.5), segments=10, ring_count=6, radius=0.2)

    # Flat cap — a squashed disc, a completely different headwear silhouette
    # from any Tier 0 unit's helmet/hood.
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, 0.02, 1.62), scale=(1.0, 1.0, 0.3), radius=0.23, depth=0.12)

    # Pickaxe: a long diagonal haft with a crossed double-pointed head — the
    # single most distinct silhouette element on the roster so far (no
    # other unit has a diagonal cross shape at its business end), and the
    # role's deep-red accent.
    part(bpy.ops.mesh.primitive_cylinder_add, wood_mat,
         (0.4, 0.35, 0.85), rotation=(1.1, 0, 0.35), radius=0.04, depth=0.7)
    for ang in (0.5, -0.5):
        part(bpy.ops.mesh.primitive_cone_add, pickaxe_mat,
             (0.55, 0.55, 1.1), rotation=(1.1, ang, 0.35), radius1=0.05, radius2=0.005, depth=0.3)
