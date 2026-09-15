"""assets/units/rifleman_<facing>.png — GameEnums.UnitType.REDCOAT (Tier 2 Ranged).

Filename stays "rifleman": UnitVisuals._texture_key() keeps the pre-rename art
key even though the enum became REDCOAT (design_doc.md Tier 2 rename).

Tier 2 ranged, and the reference model the whole soldier rig was designed
against. Pair-mate of redcoat.py: same shako and build, separated by role colour
and by carry — this one at PORT ARMS, rifle diagonal across the body with the
muzzle high, which gives the figure a long asymmetric axis that survives
minification where a centred barrel just reads as a stalk.

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

TIER = 2
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
SHAKO = (0.216, 0.208, 0.235)

BUTT = (0.185, -0.155, FIGURE_WEAPON_Z)
MUZZLE = (-0.155, 0.440, FIGURE_WEAPON_Z)


def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    coat_light = flat_material("CoatLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    steel = flat_material("Steel", STEEL)
    wood = flat_material("Wood", WOOD)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    shako = flat_material("Shako", SHAKO)

    soldier_boots(boot)
    soldier_pack(coat_dark, belt)
    left_shoulder, right_shoulder = soldier_torso(coat)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=3)

    right_hand = along(BUTT, MUZZLE, 0.26)[:2] + (FIGURE_ARM_Z,)
    left_hand = along(BUTT, MUZZLE, 0.60)[:2] + (FIGURE_ARM_Z,)
    soldier_arm(sleeve, coat_dark, skin, right_shoulder, right_hand, brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, left_hand, brass_material=brass)

    bone(steel, along(BUTT, MUZZLE, 0.42), MUZZLE, 0.017)
    bone(wood, BUTT, along(BUTT, MUZZLE, 0.46), 0.030)
    part(bpy.ops.mesh.primitive_cube_add, wood, BUTT,
         rotation=(0.0, 0.0, -0.51), scale=(0.055, 0.105, 0.042), size=1.0)
    bone(steel, MUZZLE, along(BUTT, MUZZLE, 1.16), 0.010)
    for t in (0.50, 0.72):
        part(bpy.ops.mesh.primitive_cylinder_add, steel, along(BUTT, MUZZLE, t),
             rotation=(1.5708, 0.0, -0.51), vertices=8, radius=0.025, depth=0.014)
    part(bpy.ops.mesh.primitive_uv_sphere_add, steel, along(BUTT, MUZZLE, 0.355),
         rotation=(0.0, 0.0, -0.51), scale=(0.032, 0.020, 0.012),
         segments=8, ring_count=5, radius=1.0)

    soldier_head(shako, radius=0.090, height=0.120, peak=0.085,
                 band_material=belt, badge_material=brass, collar_material=coat_dark)
