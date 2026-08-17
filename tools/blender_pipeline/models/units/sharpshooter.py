"""assets/units/sharpshooter_<facing>.png — Tier 3 Ranged. A draped
hooded cloak and a scoped rifle replace the earlier Ranged units' visible
tunic+cap silhouette — a concealment specialist reads differently in
outline from an infantry-line rifleman even before color.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

CLOAK_COLOR = (0.24, 0.26, 0.22)  # Muted drab green-grey — reads as camouflage/concealment, distinct from every earlier coat hue.
BOOT_COLOR = (0.12, 0.11, 0.1)
SKIN_COLOR = (0.72, 0.56, 0.46)
RIFLE_COLOR = (0.05, 0.1, 0.45)  # Ranged role accent: deep blue.
SCOPE_COLOR = (0.15, 0.14, 0.13)


def build():
    cloak_mat = flat_material("Cloak", CLOAK_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    rifle_mat = flat_material("Rifle", RIFLE_COLOR)
    scope_mat = flat_material("Scope", SCOPE_COLOR)

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, cloak_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    # Cloaked torso: a wide, straight-sided cylinder (not tapered like a
    # fitted tunic) — a draped, bulkier silhouette than any earlier unit's torso.
    part(bpy.ops.mesh.primitive_cylinder_add, cloak_mat,
         (0, 0, 1.05), radius=0.36, depth=0.65)
    sash(rifle_mat, (0, 0, 1.05), 0.36)

    part(bpy.ops.mesh.primitive_cylinder_add, cloak_mat,
         (-0.28, 0.25, 1.1), rotation=(1.2, 0, -0.1), radius=0.09, depth=0.45)
    part(bpy.ops.mesh.primitive_cylinder_add, cloak_mat,
         (0.28, 0.02, 1.05), rotation=(0.5, 0, 0.4), radius=0.09, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.4, 0.38, 1.15), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.38, -0.08, 1.02), segments=8, ring_count=5, radius=0.07)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.55), segments=10, ring_count=6, radius=0.19)

    # Hood: a cone draped over the head, wider at the base than
    # Toxophilite's hood — cloaks the shoulders too, not just the head, a
    # bulkier concealment-focused silhouette.
    part(bpy.ops.mesh.primitive_cone_add, cloak_mat,
         (0, -0.02, 1.72), radius1=0.28, radius2=0.06, depth=0.34)

    # Scoped rifle: a long barrel with a small cylindrical scope mounted on
    # top — the scope silhouette is unique on the roster, immediately
    # readable as "sniper" rather than "infantry rifle."
    part(bpy.ops.mesh.primitive_cylinder_add, rifle_mat,
         (0.05, 0.5, 1.15), rotation=(1.3, 0, -0.2), radius=0.035, depth=0.9)
    part(bpy.ops.mesh.primitive_cylinder_add, scope_mat,
         (0.05, 0.35, 1.28), rotation=(1.3, 0, -0.2), radius=0.025, depth=0.22)
