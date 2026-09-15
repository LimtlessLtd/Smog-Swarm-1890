"""assets/units/yeoman_marksman_<facing>.png — GameEnums.UnitType.YEOMAN_MARKSMAN (Tier 1 Ranged).

Tier 1 ranged — the first firearm unit, so the Gunpowder depletion penalty
starts here (GameEnums' own note).

Silhouette: the WIDEST headgear on the roster, a slouch hat at radius 0.135 —
half again a shako. Against rifleman.py, which is the same pose and role two
tiers up, the hat alone separates them at any zoom, and the musket is carried
lower and flatter than a shako unit's port arms.

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

TIER = 1
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
HAT = (0.376, 0.333, 0.255)

BUTT = (0.215, -0.120, FIGURE_WEAPON_Z)
MUZZLE = (-0.195, 0.390, FIGURE_WEAPON_Z)


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
    hat = flat_material("Hat", HAT)

    soldier_boots(boot)
    soldier_pack(coat_dark, belt, back=-0.145, width=0.115)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=0.98)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=3)

    right_hand = along(BUTT, MUZZLE, 0.28)[:2] + (FIGURE_ARM_Z,)
    left_hand = along(BUTT, MUZZLE, 0.62)[:2] + (FIGURE_ARM_Z,)
    soldier_arm(sleeve, coat_dark, skin, right_shoulder, right_hand, brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, left_hand, brass_material=brass)

    bone(steel, along(BUTT, MUZZLE, 0.44), MUZZLE, 0.016)
    bone(wood, BUTT, along(BUTT, MUZZLE, 0.48), 0.029)
    part(bpy.ops.mesh.primitive_cube_add, wood, BUTT,
         rotation=(0.0, 0.0, -0.68), scale=(0.052, 0.100, 0.040), size=1.0)
    for t in (0.52, 0.74):
        part(bpy.ops.mesh.primitive_cylinder_add, steel, along(BUTT, MUZZLE, t),
             rotation=(1.5708, 0.0, -0.68), vertices=8, radius=0.024, depth=0.014)

    # Slouch hat: a wide soft brim with a low crown inside it.
    soldier_head(hat, radius=0.135, height=0.055, peak=None,
                 collar_material=coat_dark)
    part(bpy.ops.mesh.primitive_cylinder_add, hat, (0.0, 0.105, FIGURE_ARM_Z + 0.155),
         vertices=12, radius=0.072, depth=0.060)
    part(bpy.ops.mesh.primitive_torus_add, belt, (0.0, 0.105, FIGURE_ARM_Z + 0.150),
         major_radius=0.074, minor_radius=0.012)
