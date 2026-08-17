"""assets/units/toxophilite_<facing>.png — Tier 0 Ranged, no Gunpowder
upkeep by design (UnitCatalog.gd comment: "arrows aren't a tracked
resource"). Ranged role accent is cobalt-blue (Style DNA), carried by the
bow/string and quiver.

Shares truncheoneer.py's leg/torso/belt/collar proportions (same body-plan
template, per user sign-off) but deliberately different headwear (a soft
hood, not a round custodian helmet) and a long bow silhouette instead of a
compact held weapon — both role/unit distinguishability requirements the
user asked to be checked explicitly before batch-producing the rest.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, curved_part, sash  # noqa: E402

COAT_COLOR = (0.32, 0.28, 0.2)   # Earthy leather/canvas — distinct from the truncheoneer's dark wool.
BOOT_COLOR = (0.14, 0.12, 0.11)
BELT_COLOR = (0.32, 0.22, 0.14)
SKIN_COLOR = (0.75, 0.6, 0.5)
HOOD_COLOR = (0.28, 0.24, 0.18)
BOW_COLOR = (0.05, 0.1, 0.45)    # Ranged role accent: deep blue (user asked deeper/richer than the earlier lighter cobalt).


def build():
    coat_mat = flat_material("Coat", COAT_COLOR)
    boot_mat = flat_material("Boot", BOOT_COLOR)
    belt_mat = flat_material("Belt", BELT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    hood_mat = flat_material("Hood", HOOD_COLOR)
    bow_mat = flat_material("Bow", BOW_COLOR)

    for side, forward in ((-0.14, 0.0), (0.14, -0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
             (side, forward, 0.35), scale=(0.6, 0.6, 1.0),
             radius=0.14, depth=0.7)
        part(bpy.ops.mesh.primitive_cube_add, boot_mat,
             (side, forward + 0.05, 0.06), scale=(0.16, 0.22, 0.08), size=1.0)

    part(bpy.ops.mesh.primitive_cone_add, coat_mat,
         (0, 0, 1.05), radius1=0.32, radius2=0.27, depth=0.6)

    # Role-accent sash — bigger, bolder cobalt-blue patch than the
    # bow/quiver alone (same fix as truncheoneer.py's own sash).
    sash(bow_mat, (0, 0, 1.05), 0.3)

    part(bpy.ops.mesh.primitive_cylinder_add, belt_mat,
         (0, 0, 0.78), scale=(1.0, 1.0, 0.12), radius=0.32, depth=1.0)

    # Quiver: a tilted cylinder slung on the back — reads as "carrying
    # arrows" at a glance, a load-bearing silhouette element the melee unit
    # has no equivalent of.
    part(bpy.ops.mesh.primitive_cylinder_add, bow_mat,
         (-0.1, -0.25, 1.25), rotation=(-0.3, 0.1, 0),
         radius=0.09, depth=0.5)

    # Arms: left arm extended forward gripping the bow stave, right arm
    # bent back at the drawn-string hand — a nocked/ready pose, not a
    # neutral stand.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (-0.28, 0.3, 1.05), rotation=(1.3, 0, -0.15),
         radius=0.08, depth=0.5)
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0.28, -0.05, 1.05), rotation=(0.3, 0, 0.5),
         radius=0.08, depth=0.4)

    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, 0, 1.55), segments=10, ring_count=6, radius=0.2)

    # Hood: a cone rather than the truncheoneer's rounded helmet+brim — a
    # different silhouette from directly overhead, not just a different color.
    part(bpy.ops.mesh.primitive_cone_add, hood_mat,
         (0, -0.03, 1.68), radius1=0.24, radius2=0.05, depth=0.32)

    # Bow: a real arc (curved_part, Bezier-based) held forward in the left
    # hand, plus a taut string — the single biggest patch of the ranged
    # role's blue accent, and a silhouette element no other Tier 0 unit has.
    curved_part(bow_mat, (-0.42, 0.42, 1.05), (0, 1.5708, 0),
                points=[(-0.22, 0, 0), (0.06, 0, 0), (0.22, 0, 0)], bevel_depth=0.025)
    part(bpy.ops.mesh.primitive_cylinder_add, bow_mat,
         (-0.42, 0.42, 1.05), rotation=(0, 0, 0),
         scale=(1.0, 1.0, 1.0), radius=0.008, depth=0.42)

    # Third-pass detail: hands at both grip points, arrow fletching poking
    # from the quiver, and a forearm bracer — small touches matching
    # truncheoneer.py's own third pass.
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (-0.42, 0.42, 1.05), segments=8, ring_count=5, radius=0.07)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.4, -0.15, 0.9), segments=8, ring_count=5, radius=0.07)

    fletching_mat = flat_material("Fletching", (0.85, 0.85, 0.8))
    for offset in (-0.05, 0.0, 0.05):
        part(bpy.ops.mesh.primitive_cone_add, fletching_mat,
             (-0.1 + offset, -0.2, 1.5), rotation=(-0.3, 0.1, 0),
             radius1=0.02, radius2=0.005, depth=0.18)

    bracer_mat = flat_material("Bracer", (0.2, 0.16, 0.12))
    part(bpy.ops.mesh.primitive_cylinder_add, bracer_mat,
         (-0.36, 0.36, 1.05), rotation=(1.3, 0, -0.15),
         radius=0.1, depth=0.08)
