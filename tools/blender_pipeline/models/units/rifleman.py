"""assets/units/rifleman_<facing>.png — GameEnums.UnitType.REDCOAT (Tier 2
Ranged, requires_gunpowder). Filename stays "rifleman" — UnitVisuals.
_texture_key() keeps the pre-rename art key even though the enum became
REDCOAT (design_doc.md Tier 2 rename). Same standardized-uniform tier as
redcoat.py (Bayoneteer) but a forage cap instead of a shako and a rifle
held in an aiming stance instead of fixed-bayonet present-arms — both
units share a near-identical tunic silhouette on purpose (same tier,
same regiment) but stay distinguishable by headwear/weapon/pose.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.16, 0.15, 0.16)
BOOT_COLOR = (0.08, 0.07, 0.06)
BELT_COLOR = (0.85, 0.82, 0.75)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.1, 0.09, 0.09)
RIFLE_COLOR = (0.05, 0.1, 0.45)  # Ranged role accent: deep blue.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    rifle_mat = flat_material("Rifle", RIFLE_COLOR)
    wood_mat = flat_material("Stock", (0.3, 0.2, 0.12))

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.34, radius2=0.28, depth=0.6)

    part(bpy.ops.mesh.primitive_torus_add, belt_mat,
         (0, 0, 1.05), rotation=(0.35, 0.9, 0), major_radius=0.33, minor_radius=0.03)
    sash(rifle_mat, (0, 0, 1.05), 0.3, diagonal_rotation=(-0.35, 0.9, 0))

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.1), radius=0.32, depth=1.0)

    # Arms: aiming stance, rifle raised and angled forward — matches
    # Yeoman Marksman's pose family (both Ranged), but the rifle geometry
    # itself is thicker/more military than that unit's plainer hunting rifle.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.28, 0.28, 1.1), rotation=(1.2, 0, -0.1), radius=0.08, depth=0.45)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.28, 0.05, 1.05), rotation=(0.5, 0, 0.4), radius=0.08, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.4, 0.42, 1.15), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.38, -0.05, 1.02), segments=8, ring_count=5, radius=0.07)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.53), segments=10, ring_count=6, radius=0.2)

    # Forage cap: a short flat-topped cylinder with a small peak — shorter
    # and plainer than Bayoneteer's tall shako, a different silhouette
    # despite the shared uniform elsewhere.
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, 0.02, 1.64), radius=0.2, depth=0.12)
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, 0.16, 1.6), scale=(1.0, 1.0, 0.15), radius=0.1, depth=0.08)

    part(bpy.ops.mesh.primitive_cylinder_add, rifle_mat,
         (0.05, 0.5, 1.15), rotation=(1.3, 0, -0.2), radius=0.04, depth=0.85)
    part(bpy.ops.mesh.primitive_cube_add, wood_mat,
         (0.3, -0.05, 1.0), scale=(0.05, 0.14, 0.07), size=1.0, rotation=(1.3, 0, -0.2))
