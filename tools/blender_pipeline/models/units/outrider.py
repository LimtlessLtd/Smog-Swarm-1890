"""assets/units/outrider_<facing>.png — Tier 0 Special, UNARMED_SCOUT
(UnitCatalog.gd: damage_multiplier 0.0, "genuinely cannot fight"; move_speed
1.6x, vision_radius 2 — reconnaissance, not combat). Special role accent is
violet-purple (Style DNA); with no weapon to carry it, it lands on a
dispatch satchel instead — the ability name ("scout", not "trooper") is
the reason a courier bag reads more truthfully than a sword would.

Mounted — a genuinely different body plan from truncheoneer.py/
toxophilite.py's standing-infantry template, not just a recolor. Horse body
runs along local +Y (this pipeline's own "front" axis, see
render_common.py's yaw convention) so the mount's facing and the rider's
facing are the same thing by construction.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, sash, curved_part  # noqa: E402

HORSE_COLOR = (0.35, 0.25, 0.18)
HORSE_DARK_COLOR = (0.18, 0.13, 0.1)  # Legs/tail — a shade darker, breaks the body into readable parts.
COAT_COLOR = (0.3, 0.28, 0.24)
SKIN_COLOR = (0.75, 0.6, 0.5)
CAP_COLOR = (0.22, 0.2, 0.18)
SATCHEL_COLOR = (0.3, 0.03, 0.42)  # Special role accent: deep purple (user asked deeper/richer than the earlier lighter violet).


def build():
    horse_mat = flat_material("Horse", HORSE_COLOR)
    horse_dark_mat = flat_material("HorseDark", HORSE_DARK_COLOR)
    coat_mat = flat_material("Coat", COAT_COLOR)
    skin_mat = flat_material("Skin", SKIN_COLOR)
    cap_mat = flat_material("Cap", CAP_COLOR)
    satchel_mat = flat_material("Satchel", SATCHEL_COLOR)

    # Horse body: a cylinder lying along Y (the pipeline's "front" axis),
    # so it's the same shape regardless of which of the 8 renders is looking
    # at it — only the camera yaw changes, not this object's own orientation.
    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0, 0.55), rotation=(1.5708, 0, 0),
         radius=0.22, depth=0.75)

    # Neck + head, angled up and forward from the body's +Y end.
    part(bpy.ops.mesh.primitive_cylinder_add, horse_mat,
         (0, 0.45, 0.75), rotation=(-0.9, 0, 0),
         radius=0.12, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, horse_mat,
         (0, 0.62, 1.0), segments=8, ring_count=5, radius=0.13)

    # Four legs — thin cylinders at each corner, straight down to the ground.
    for side in (-0.14, 0.14):
        for forward in (0.28, -0.28):
            part(bpy.ops.mesh.primitive_cylinder_add, horse_dark_mat,
                 (side, forward, 0.25), radius=0.06, depth=0.5)

    # Tail, trailing down off the -Y end.
    part(bpy.ops.mesh.primitive_cone_add, horse_dark_mat,
         (0, -0.42, 0.45), rotation=(0.4, 0, 0),
         radius1=0.08, radius2=0.02, depth=0.35)

    # Rider: shorter torso than a standing unit (legs are implied, straddling
    # the horse, not modeled separately — they'd be fully occluded by the
    # horse's own body at this camera angle anyway), seated on the horse's
    # back. Pulled back to Y=-0.1 (was 0.05) — at 0.05 the rider's own sash
    # sat close enough to the neck's Y=0.45 base that some yaw angles
    # visually buried the accent behind the neck (measured on a real
    # render, not assumed): a 0.55-unit Y gap instead of 0.4 keeps rider
    # and neck separated in screen projection at every facing, not just some.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_mat,
         (0, -0.1, 1.0), radius=0.2, depth=0.4)

    # Role-accent sash — bigger, bolder violet-purple patch than the
    # satchel alone (same fix as the other two Tier 0 units' own sash).
    sash(satchel_mat, (0, -0.1, 1.0), 0.2)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0, -0.1, 1.28), segments=10, ring_count=6, radius=0.16)
    part(bpy.ops.mesh.primitive_cone_add, cap_mat,
         (0, -0.13, 1.4), radius1=0.18, radius2=0.03, depth=0.16)

    # Dispatch satchel: slung at the rider's side, enlarged and pushed
    # further out past the horse's own body radius (0.22) than the first
    # pass's (0.1, 0.16, 0.14) scale — that version stayed mostly inside
    # the horse's silhouette from several yaw angles instead of reading as
    # its own distinct shape. The sole carrier of this unit's role-accent
    # color alongside the sash, standing in for the weapon every other
    # role's accent also rides on.
    part(bpy.ops.mesh.primitive_cube_add, satchel_mat,
         (0.3, 0.0, 0.92), scale=(0.13, 0.2, 0.17), size=1.0, rotation=(0, 0, 0.3))

    # Third-pass detail: a saddle under the rider, reins running to the
    # horse's head, and rider hands — small touches matching the other two
    # Tier 0 units' own third pass.
    saddle_mat = flat_material("Saddle", (0.22, 0.15, 0.1))
    part(bpy.ops.mesh.primitive_cube_add, saddle_mat,
         (0, -0.1, 0.78), scale=(0.16, 0.35, 0.06), size=1.0)

    curved_part(saddle_mat, (0, 0.15, 0.95), (1.5708, 0, 0),
                points=[(-0.35, 0, 0), (-0.15, 0, -0.1), (0.05, 0, -0.05)], bevel_depth=0.012)
    part(bpy.ops.mesh.primitive_uv_sphere_add, skin_mat,
         (0.08, 0.18, 0.9), segments=8, ring_count=5, radius=0.07)
