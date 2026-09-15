"""assets/units/toxophilite_<facing>.png — GameEnums.UnitType.TOXOPHILITE (Tier 0 Ranged).

Tier 0 ranged — a bow, so no Gunpowder upkeep (GameEnums' own note).

Silhouette: the only ARC on the entire roster. A drawn longbow held across the
body projects as a long curve, which is unmistakable at any zoom that resolves
the figure at all and shares nothing with the straight barrels every other
ranged unit carries. Slight build, small hood, no pack.

Built on render_common's soldier rig (soldier_torso/soldier_arm/soldier_head),
so every joint is a real articulation and the interior trim sits on FIGURE_TRIM_Z
where it cannot widen the silhouette. See that block for why Z is draw order.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, bone, limb, hand, along, role_coat_color, ROLE_RANGED,
    soldier_boots, soldier_torso, soldier_arm, soldier_head, soldier_trim,
    soldier_pack, FIGURE_ARM_Z, FIGURE_TRIM_Z, FIGURE_TORSO_TOP, FIGURE_WEAPON_Z,
)

TIER = 0
COAT = role_coat_color(ROLE_RANGED, TIER)
COAT_DARK = tuple(c * 0.70 for c in COAT)
COAT_LIGHT = tuple(min(1.0, c * 1.26 + 0.02) for c in COAT)
SLEEVE = tuple(c * 0.80 for c in COAT)
SKIN = (0.769, 0.600, 0.486)
BELT = (0.878, 0.851, 0.780)
STEEL = (0.310, 0.322, 0.353)
WOOD = (0.416, 0.278, 0.157)
BOOT = (0.157, 0.141, 0.129)
BRASS = (0.796, 0.635, 0.259)
BOW = (0.435, 0.298, 0.161)
HOOD = (0.333, 0.310, 0.267)

NOCK_A = (0.300, -0.185, FIGURE_WEAPON_Z)
NOCK_B = (-0.230, 0.395, FIGURE_WEAPON_Z)
GRIP = (0.070, 0.115, FIGURE_ARM_Z)
DRAW = (0.195, 0.048, FIGURE_ARM_Z)


def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    coat_light = flat_material("CoatLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    bow_mat = flat_material("Bow", BOW)
    hood = flat_material("Hood", HOOD)

    soldier_boots(boot)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=0.93)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=2, pouch=False,
                 cross_belts=False)
    # Quiver over the right shoulder, arrows showing as a bundle of nocks.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_dark, (0.155, -0.125, FIGURE_TRIM_Z + 0.010),
         rotation=(0.0, 0.0, 0.0), vertices=10, radius=0.052, depth=0.030)
    for i in range(3):
        part(bpy.ops.mesh.primitive_cylinder_add, belt,
             (0.130 + i * 0.026, -0.120, FIGURE_TRIM_Z + 0.022),
             vertices=6, radius=0.008, depth=0.020)

    soldier_arm(sleeve, coat_dark, skin, left_shoulder, GRIP, elbow_out=0.055)
    soldier_arm(sleeve, coat_dark, skin, right_shoulder, DRAW, elbow_out=0.090)

    # The bow: a curve through three points, not a straight stave, so the arc
    # survives as an arc when minified.
    belly = (0.055, 0.135, FIGURE_WEAPON_Z)
    bone(bow_mat, NOCK_A, belly, 0.017)
    bone(bow_mat, belly, NOCK_B, 0.017)
    part(bpy.ops.mesh.primitive_uv_sphere_add, bow_mat, belly,
         segments=8, ring_count=5, radius=0.019)
    # String, drawn back to the loose hand.
    bone(belt, NOCK_A, DRAW, 0.006)
    bone(belt, DRAW, NOCK_B, 0.006)
    bone(belt, DRAW, (-0.010, 0.235, FIGURE_WEAPON_Z), 0.008)

    soldier_head(hood, radius=0.082, height=0.105, peak=0.052,
                 collar_material=coat_dark)
