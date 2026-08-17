"""assets/units/redcoat_<facing>.png — GameEnums.UnitType.BAYONETEER (Tier 2
Melee). Filename stays "redcoat" — UnitVisuals._texture_key() keeps the
pre-rename art key even though the enum became BAYONETEER (design_doc.md
Tier 2 rename; see that function's own comment). Standardized military
dress (Style DNA: "Tier 0-3 progressively more standardized/heavier") —
a tall shako and a fixed-bayonet rifle instead of Navvy's flat cap and
pickaxe or Truncheoneer's custodian helmet and truncheon.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.16, 0.15, 0.16)   # Near-black formal tunic — deliberately NOT red, so the deep-red sash/blade stay the only red instead of two competing reds.
BOOT_COLOR = (0.08, 0.07, 0.06)
BELT_COLOR = (0.85, 0.82, 0.75)   # Cream cross-belt leather — authentic Redcoat detail, neutral so it doesn't compete with the role accent.
SKIN_COLOR = (0.72, 0.56, 0.46)
SHAKO_COLOR = (0.1, 0.09, 0.09)
BLADE_COLOR = (0.5, 0.03, 0.05)   # Melee role accent: deep red.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    shako_mat = flat_material("Shako", SHAKO_COLOR)
    blade_mat = flat_material("Blade", BLADE_COLOR)
    wood_mat = flat_material("Stock", (0.3, 0.2, 0.12))

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0), radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.34, radius2=0.28, depth=0.6)

    # Cross-belt: a straight (not diagonal-torus) cream band — a
    # single flat strap across the chest, distinct in shape from every
    # other unit's sash/bandolier so far.
    part(bpy.ops.mesh.primitive_torus_add, belt_mat,
         (0, 0, 1.05), rotation=(0.35, 0.9, 0), major_radius=0.33, minor_radius=0.03)
    sash(blade_mat, (0, 0, 1.05), 0.3, diagonal_rotation=(-0.35, 0.9, 0))  # Opposite diagonal from the cross-belt — an X, not two parallel stripes.

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.1), radius=0.32, depth=1.0)

    # Arms: fixed-bayonet present-arms stance — rifle held vertically
    # in front, not diagonally slung like Yeoman Marksman's aiming pose.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.25, 0.15, 1.0), rotation=(0.3, 0, 0.3), radius=0.08, depth=0.5)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.25, 0.15, 0.95), rotation=(0.5, 0, -0.3), radius=0.08, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.3, 0.3, 1.2), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.3, 0.32, 0.75), segments=8, ring_count=5, radius=0.07)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.53), segments=10, ring_count=6, radius=0.2)

    # Shako: a tall straight-sided cylinder, MUCH taller than any earlier
    # headwear (pillbox, flat cap, wide hat) — the single tallest silhouette
    # on the roster so far, unmistakable even in outline alone.
    part(bpy.ops.mesh.primitive_cylinder_add, shako_mat,
         (0, 0, 1.85), radius=0.22, depth=0.4)
    part(bpy.ops.mesh.primitive_cylinder_add, shako_mat,
         (0, 0, 1.66), scale=(1.0, 1.0, 0.2), radius=0.25, depth=0.1)  # Peak/brim.

    # Rifle with fixed bayonet: vertical barrel, thin blade cone at the tip
    # — a straight vertical line breaking the figure's own silhouette top,
    # unlike any earlier unit's diagonal weapon.
    part(bpy.ops.mesh.primitive_cylinder_add, wood_mat,
         (-0.3, 0.35, 1.3), radius=0.035, depth=0.9)
    part(bpy.ops.mesh.primitive_cone_add, blade_mat,
         (-0.3, 0.35, 1.85), radius1=0.03, radius2=0.002, depth=0.3)
