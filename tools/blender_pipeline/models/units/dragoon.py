"""assets/units/dragoon_<facing>.png — Tier 3 Special, CHARGE_KNOCKBACK
ability. A heavier armored horse and a forward-leveled lance replace
Chasseur's plain coat and holstered pistol — a charging shock-cavalry
silhouette (weapon projecting far forward past the horse's own head) is
unmistakably different from Chasseur's compact mounted-firearm pose even
at a glance.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash, curved_part  # noqa: E402

HORSE_COLOR = (0.32, 0.24, 0.17)
HORSE_DARK_COLOR = (0.16, 0.12, 0.09)
ARMOR_COLOR = (0.28, 0.28, 0.3)  # Grey-steel cuirass — a hard, distinct material from every cloth coat on the roster.
COAT_COLOR = (0.18, 0.17, 0.19)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.16, 0.15, 0.16)
LANCE_COLOR = (0.3, 0.03, 0.42)  # Special role accent: deep purple.


def build():
    horse_mat = flat_material("Horse", HORSE_COLOR)
    horse_dark_mat = flat_material("HorseDark", HORSE_DARK_COLOR)
    armor_mat = flat_material("Armor", ARMOR_COLOR)
    coat_mat = flat_material("Coat", COAT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    lance_mat = flat_material("Lance", LANCE_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0, 0.55), rotation=(1.5708, 0, 0), radius=0.23, depth=0.78)
    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0.46, 0.75), rotation=(-0.9, 0, 0), radius=0.12, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, horse_mat,
         (0, 0.63, 1.0), segments=8, ring_count=5, radius=0.13)

    # Horse armor plate: a flattened box over the chest — the horse itself
    # is visibly armored, not just the rider, a first for the mounted roster.
    part(bpy.ops.mesh.primitive_cube_add, armor_mat,
         (0, 0.32, 0.62), scale=(0.24, 0.16, 0.2), size=1.0, rotation=(0.1, 0, 0))

    for side in (-0.14, 0.14):
        for forward in (0.28, -0.28):
            part(bpy.ops.mesh.primitive_cylinder_add, horse_dark_mat,
                 (side, forward, 0.25), radius=0.065, depth=0.5)

    part(bpy.ops.mesh.primitive_cone_add, horse_dark_mat,
         (0, -0.43, 0.45), rotation=(0.4, 0, 0), radius1=0.08, radius2=0.02, depth=0.35)

    saddle_mat = flat_material("Saddle", (0.2, 0.14, 0.09))
    part(bpy.ops.mesh.primitive_cube_add, saddle_mat,
         (0, -0.1, 0.78), scale=(0.17, 0.35, 0.06), size=1.0)

    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0, -0.1, 1.0), radius=0.21, depth=0.4)

    # Cuirass: a chest plate over the tunic — armored rider, matching the
    # armored horse, a bulkier torso silhouette than Chasseur's plain coat.
    part(bpy.ops.mesh.primitive_cylinder_add, armor_mat,
         (0, -0.02, 1.02), scale=(1.05, 0.9, 1.0), radius=0.19, depth=0.32)
    sash(lance_mat, (0, -0.1, 1.0), 0.21)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, -0.1, 1.28), segments=10, ring_count=6, radius=0.16)
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, -0.13, 1.42), radius=0.17, depth=0.14)

    # Lance: a long straight shaft leveled forward, projecting well past the
    # horse's own head — the longest single silhouette element on the
    # roster, and unmistakably a charging-cavalry weapon rather than a
    # sidearm.
    part(bpy.ops.mesh.primitive_cylinder_add, lance_mat,
         (0, 0.75, 1.05), rotation=(1.5708, 0, 0), radius=0.025, depth=1.1)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.05, 0.25, 0.98), segments=8, ring_count=5, radius=0.07)
