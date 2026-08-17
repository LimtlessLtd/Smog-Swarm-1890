"""assets/units/truncheoneer_<facing>.png — Tier 0 Melee (UnitCatalog.gd's
"Free Ammo" starting tier). Melee role accent is rust-red (Style DNA,
assets/units/README.md), carried by the truncheon here rather than a sash/
trim, matching that doc's "the accent is the weapon/insignia, not a wash
over the whole figure" rule.

Second pass (first pass was a 5-primitive torso+head+helmet+truncheon
cluster) — user asked for more geometric detail before the remaining
17 units: separate legs/boots, two arms in a ready pose (one gripping the
truncheon forward-down, not floating disconnected from the body), a coat
collar flare, and a helmet with an actual brim disc instead of a plain
flattened sphere. render_common.part() (this script's own boilerplate,
promoted there once toxophilite.py/outrider.py needed the same helper).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash  # noqa: E402

COAT_COLOR = (0.25, 0.24, 0.26)     # Dark, weathered Victorian wool — grounded, not the accent.
BOOT_COLOR = (0.14, 0.12, 0.11)
BELT_COLOR = (0.32, 0.22, 0.14)     # Leather — neutral, doesn't compete with the truncheon's role accent.
SKIN_COLOR = (0.75, 0.6, 0.5)
HELMET_COLOR = (0.12, 0.12, 0.14)   # Custodian helmet — near-black.
TRUNCHEON_COLOR = (0.5, 0.03, 0.05)  # Melee role accent: deep red (user asked deeper/richer than the earlier lighter rust-red).


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    helmet_mat = flat_material("Helmet", HELMET_COLOR)
    truncheon_mat = flat_material("Truncheon", TRUNCHEON_COLOR)

    # Legs: two separate tapered cylinders (a stride stance — one slightly
    # forward) with a small flattened-box boot capping each.
    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0),
             radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    # Torso, tapered (wider at the shoulders) rather than a straight cylinder.
    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.34, radius2=0.28, depth=0.6)

    # Role-accent sash — a genuinely bigger, bolder patch of rust-red than
    # the truncheon alone (user feedback: the weapon-only accent read too
    # small once this is real 3D geometry, not flat painted color).
    sash(truncheon_mat, (0, 0, 1.05), 0.31)

    # Belt: a flattened, slightly wider cylinder band at the waistline.
    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.12), radius=0.33, depth=1.0)

    # Coat collar: a short wide cone flaring out at the neckline — breaks
    # the torso/head silhouette into two readable pieces instead of one
    # unbroken taper.
    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.38), radius1=0.3, radius2=0.16, depth=0.16)

    # Arms: left arm down at the side, right arm raised and bent forward,
    # gripping distance for the truncheon.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.32, 0.0, 1.0), rotation=(0.15, 0, 0.1),
         radius=0.08, depth=0.55)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.3, 0.18, 1.15), rotation=(1.0, 0, 0.25),
         radius=0.08, depth=0.45)

    # Head + helmet with a distinct brim disc — the custodian helmet's most
    # recognizable feature.
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.55), segments=10, ring_count=6, radius=0.2)
    part(bpy.ops.mesh.primitive_uv_sphere_add, helmet_mat,
         (0, 0, 1.68), scale=(1.0, 1.0, 0.8), segments=10, ring_count=6, radius=0.24)
    part(bpy.ops.mesh.primitive_cylinder_add, helmet_mat,
         (0, 0, 1.62), scale=(1.0, 1.0, 0.25), radius=0.27, depth=0.1)

    # Truncheon: gripped at the raised right hand, angled forward-down —
    # a held weapon, not a detached prop. Still the single largest patch of
    # the melee role's rust-red accent so it stays instantly identifiable.
    part(bpy.ops.mesh.primitive_cylinder_add, truncheon_mat,
         (0.42, 0.35, 0.95), rotation=(1.1, 0, 0.35),
         radius=0.06, depth=0.5)

    # Third-pass detail (user asked for "a bit more" after the sash fix):
    # hands grounding both arm ends, a belt buckle, and epaulette shoulder
    # pads — small touches, not a redesign.
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.32, -0.02, 0.7), segments=8, ring_count=5, radius=0.08)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.4, 0.32, 0.98), segments=8, ring_count=5, radius=0.08)

    buckle_mat = flat_material("Buckle", (0.55, 0.45, 0.2))
    part(bpy.ops.mesh.primitive_cube_add, buckle_mat,
         (0, 0.32, 0.78), scale=(0.06, 0.02, 0.05), size=1.0)

    for side in (-0.3, 0.3):
        part(bpy.ops.mesh.primitive_cube_add, coat_mat,
             (side, 0.05, 1.3), scale=(0.1, 0.12, 0.04), size=1.0)
