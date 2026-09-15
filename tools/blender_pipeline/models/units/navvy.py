"""assets/units/navvy_<facing>.png — GameEnums.UnitType.NAVVY (Tier 1 Melee).

Tier 1 melee — a labourer, not a soldier, and drawn as one.

Silhouette: SHIRTSLEEVES. No coat skirt, no cross-belts, no pack, a small flat
cap, and a pickaxe carried over the shoulder as a long diagonal with a hard T
head on the end. The T is the mark: every other melee unit ends its weapon in a
point, a blade or a ball.

Built on render_common's soldier rig (soldier_torso/soldier_arm/soldier_head),
so every joint is a real articulation and the interior trim sits on FIGURE_TRIM_Z
where it cannot widen the silhouette. See that block for why Z is draw order.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, bone, limb, hand, along, role_coat_color, ROLE_MELEE,
    soldier_boots, soldier_torso, soldier_arm, soldier_head, soldier_trim,
    soldier_pack, FIGURE_ARM_Z, FIGURE_TRIM_Z, FIGURE_TORSO_TOP, FIGURE_WEAPON_Z,
)

TIER = 1
COAT = role_coat_color(ROLE_MELEE, TIER)
COAT_DARK = tuple(c * 0.70 for c in COAT)
COAT_LIGHT = tuple(min(1.0, c * 1.26 + 0.02) for c in COAT)
SLEEVE = tuple(c * 0.80 for c in COAT)
SKIN = (0.769, 0.600, 0.486)
BELT = (0.878, 0.851, 0.780)
STEEL = (0.310, 0.322, 0.353)
WOOD = (0.416, 0.278, 0.157)
BOOT = (0.157, 0.141, 0.129)
BRASS = (0.796, 0.635, 0.259)
HAFT = (0.435, 0.318, 0.184)
IRON = (0.353, 0.365, 0.384)

GRIP_LOW = (0.185, -0.055, FIGURE_ARM_Z)
GRIP_HIGH = (0.105, 0.185, FIGURE_ARM_Z)
HEAD_AT = (-0.055, 0.430, FIGURE_WEAPON_Z)


def build():
    coat = flat_material("Shirt", COAT)
    coat_dark = flat_material("ShirtDark", COAT_DARK)
    coat_light = flat_material("ShirtLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    haft = flat_material("Haft", HAFT)
    iron = flat_material("Iron", IRON)

    soldier_boots(boot, spread=0.115, length=0.090)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=1.02)
    # Braces instead of webbing, and no pouch: working dress, not uniform.
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=2, pouch=False,
                 cross_belts=False)
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cube_add, coat_dark, (side * 0.055, 0.020, FIGURE_TRIM_Z + 0.004),
             scale=(0.024, 0.230, 0.010), size=1.0)

    soldier_arm(sleeve, coat_dark, skin, right_shoulder, GRIP_LOW, elbow_out=0.085)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, GRIP_HIGH, elbow_out=0.070)

    bone(haft, GRIP_LOW, HEAD_AT, 0.023)
    # Pick head: a hard crossbar, the family's one T-shaped weapon.
    part(bpy.ops.mesh.primitive_cube_add, iron, HEAD_AT,
         rotation=(0.0, 0.0, -0.62), scale=(0.235, 0.038, 0.030), size=1.0)

    soldier_head(flat_material("Cap", (0.255, 0.243, 0.216)), radius=0.078,
                 height=0.070, peak=0.048, collar_material=coat_dark)
