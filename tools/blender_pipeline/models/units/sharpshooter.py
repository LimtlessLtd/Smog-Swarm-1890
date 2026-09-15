"""assets/units/sharpshooter_<facing>.png — GameEnums.UnitType.SHARPSHOOTER (Tier 3 Ranged).

Tier 3 ranged.

Silhouette: the LONGEST weapon and the SMALLEST head on the foot roster — a
scoped long rifle held out almost straight ahead, and a low peaked cap at radius
0.070. Narrow build, no pack, hunched forward. Against yeoman_marksman.py (wide
hat, short musket) the two ranged units read as opposites at a glance, which is
the point: they are the same role three tiers apart.

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

TIER = 3
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
CAP = (0.208, 0.220, 0.212)
SCOPE = (0.180, 0.192, 0.204)

BUTT = (0.150, -0.180, FIGURE_WEAPON_Z)
MUZZLE = (-0.055, 0.530, FIGURE_WEAPON_Z)


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
    cap = flat_material("Cap", CAP)
    scope = flat_material("Scope", SCOPE)

    soldier_boots(boot, spread=0.095, back=-0.150)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=0.90)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=2, cross_belts=False)
    # Single bandolier rather than crossed webbing.
    part(bpy.ops.mesh.primitive_cube_add, belt, (0.0, 0.010, FIGURE_TORSO_TOP + 0.004),
         rotation=(0.0, 0.0, -0.62), scale=(0.030, 0.245, 0.012), size=1.0)

    right_hand = along(BUTT, MUZZLE, 0.26)[:2] + (FIGURE_ARM_Z,)
    left_hand = along(BUTT, MUZZLE, 0.56)[:2] + (FIGURE_ARM_Z,)
    soldier_arm(sleeve, coat_dark, skin, right_shoulder, right_hand, elbow_out=0.060,
                brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, left_hand, elbow_out=0.070,
                brass_material=brass)

    bone(steel, along(BUTT, MUZZLE, 0.40), MUZZLE, 0.015)
    bone(wood, BUTT, along(BUTT, MUZZLE, 0.44), 0.028)
    part(bpy.ops.mesh.primitive_cube_add, wood, BUTT,
         rotation=(0.0, 0.0, -0.28), scale=(0.050, 0.105, 0.038), size=1.0)
    # Telescopic sight sitting proud of the barrel — this unit's own mark.
    part(bpy.ops.mesh.primitive_cylinder_add, scope, along(BUTT, MUZZLE, 0.46),
         rotation=(1.5708, 0.0, -0.28), vertices=10, radius=0.026, depth=0.165)
    for t in (0.36, 0.56):
        part(bpy.ops.mesh.primitive_cylinder_add, steel, along(BUTT, MUZZLE, t),
             rotation=(1.5708, 0.0, -0.28), vertices=8, radius=0.030, depth=0.012)

    soldier_head(cap, radius=0.070, height=0.062, peak=0.052,
                 collar_material=coat_dark)
