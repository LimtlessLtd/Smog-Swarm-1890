"""assets/units/highlander_<facing>.png — Tier 3 Melee. A kilt (flared hip
cone instead of tapered trousers) and a claymore replace every earlier
Melee unit's trousers+sidearm silhouette — the flare alone is
distinguishable from the whole roster's leg silhouette even before color.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.14, 0.13, 0.14)
KILT_COLOR = (0.22, 0.14, 0.12)  # Muted tartan-red-brown — a plausible dark tartan without needing a real pattern.
BOOT_COLOR = (0.1, 0.09, 0.08)
SPORRAN_COLOR = (0.35, 0.3, 0.24)
SKIN_COLOR = (0.72, 0.56, 0.46)
CAP_COLOR = (0.16, 0.13, 0.12)
BLADE_COLOR = (0.5, 0.03, 0.05)  # Melee role accent: deep red.


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    kilt_mat = flat_material("Kilt", KILT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    sporran_mat = flat_material("Sporran", SPORRAN_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    blade_mat = flat_material("Blade", BLADE_COLOR)

    # Bare lower legs (no trousers) below the kilt — a Highlander-specific
    # detail no other unit has.
    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, skin_mat,
             (side, forward, 0.3), scale=(0.5, 0.5, 1.0), radius=0.12, depth=0.55)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    # Kilt: a wide-flaring cone, MUCH wider at the base than any earlier
    # unit's leg/torso taper — the single most distinct silhouette element
    # on the roster below the waist.
    part(bpy.ops.mesh.primitive_cone_add, kilt_mat,
         (0, 0, 0.65), radius1=0.42, radius2=0.26, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, sporran_mat,
         (0, 0.32, 0.6), scale=(1.0, 0.6, 1.0), segments=8, ring_count=5, radius=0.1)

    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0, 0, 1.05), radius=0.3, depth=0.55)
    sash(blade_mat, (0, 0, 1.05), 0.3)

    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.3, 0.0, 1.0), rotation=(0.15, 0, 0.1), radius=0.08, depth=0.55)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.3, 0.2, 1.15), rotation=(1.0, 0, 0.25), radius=0.08, depth=0.5)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.32, -0.02, 0.7), segments=8, ring_count=5, radius=0.08)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.42, 0.38, 0.98), segments=8, ring_count=5, radius=0.08)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.5), segments=10, ring_count=6, radius=0.2)

    # Glengarry-style cap: a low, soft, boat-shaped ridge — flatter and
    # narrower than the shako/pillbox family, a third distinct headwear silhouette.
    part(bpy.ops.mesh.primitive_cylinder_add, cap_mat,
         (0, 0, 1.6), scale=(0.6, 1.0, 0.35), radius=0.22, depth=0.14)

    # Claymore: a long straight double-edged blade held forward-up — longer
    # and straighter than any earlier weapon (pickaxe/rifle/bayonet all
    # read shorter or thinner), reads as "big sword" at a glance.
    part(bpy.ops.mesh.primitive_cube_add, blade_mat,
         (0.44, 0.5, 1.1), scale=(0.035, 0.5, 0.07), size=1.0, rotation=(1.0, 0, 0.25))
