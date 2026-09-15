"""assets/units/grenadier_<facing>.png — GameEnums.UnitType.GRENADIER (Tier 1 Special).

Tier 1 special, UnitAbility.EXPLOSIVE_SPLASH.

Silhouette: the TALLEST, NARROWEST headgear — a mitre cap, which from overhead is
a small circle raised well clear of the shoulders and pointed at the front. Plus
the only unit carrying a round object in a raised hand rather than a long weapon:
a lit grenade with a spark, and a satchel of them on the hip. Nothing else on the
roster is "bulky body, tiny head, no barrel".

Built on render_common's soldier rig (soldier_torso/soldier_arm/soldier_head),
so every joint is a real articulation and the interior trim sits on FIGURE_TRIM_Z
where it cannot widen the silhouette. See that block for why Z is draw order.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, bone, limb, hand, along, role_coat_color, ROLE_SPECIAL,
    soldier_boots, soldier_torso, soldier_arm, soldier_head, soldier_trim,
    soldier_pack, FIGURE_ARM_Z, FIGURE_TRIM_Z, FIGURE_TORSO_TOP, FIGURE_WEAPON_Z,
)

TIER = 1
COAT = role_coat_color(ROLE_SPECIAL, TIER)
COAT_DARK = tuple(c * 0.70 for c in COAT)
COAT_LIGHT = tuple(min(1.0, c * 1.26 + 0.02) for c in COAT)
SLEEVE = tuple(c * 0.80 for c in COAT)
SKIN = (0.769, 0.600, 0.486)
BELT = (0.878, 0.851, 0.780)
STEEL = (0.310, 0.322, 0.353)
WOOD = (0.416, 0.278, 0.157)
BOOT = (0.157, 0.141, 0.129)
BRASS = (0.796, 0.635, 0.259)
MITRE = (0.247, 0.231, 0.267)
IRON = (0.239, 0.243, 0.251)
SPARK = (0.965, 0.784, 0.310)

THROW_HAND = (0.220, 0.255, FIGURE_ARM_Z)


def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    coat_light = flat_material("CoatLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    mitre = flat_material("Mitre", MITRE)
    iron = flat_material("Iron", IRON)
    spark = flat_material("Spark", SPARK)

    soldier_boots(boot, spread=0.115)
    soldier_pack(coat_dark, belt, back=-0.155, width=0.140)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=1.10)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=3)

    # Grenade satchel on the left hip, with three fuzes showing.
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_dark, (-0.135, -0.075, FIGURE_TRIM_Z + 0.012),
         scale=(0.085, 0.070, 0.026), segments=12, ring_count=7, radius=1.0)
    for i in range(3):
        part(bpy.ops.mesh.primitive_cylinder_add, iron,
             (-0.175 + i * 0.038, -0.072, FIGURE_TRIM_Z + 0.030),
             vertices=8, radius=0.020, depth=0.016)

    soldier_arm(sleeve, coat_dark, skin, right_shoulder, THROW_HAND, elbow_out=0.100,
                elbow_forward=0.050, brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, (-0.205, 0.145, FIGURE_ARM_Z),
                brass_material=brass)

    # The grenade itself, held up: a dark sphere with a bright spark.
    part(bpy.ops.mesh.primitive_uv_sphere_add, iron,
         (THROW_HAND[0] + 0.020, THROW_HAND[1] + 0.055, FIGURE_WEAPON_Z),
         segments=12, ring_count=7, radius=0.052)
    part(bpy.ops.mesh.primitive_uv_sphere_add, spark,
         (THROW_HAND[0] + 0.030, THROW_HAND[1] + 0.100, FIGURE_WEAPON_Z + 0.010),
         segments=8, ring_count=5, radius=0.022)

    soldier_head(mitre, radius=0.070, height=0.170, peak=0.046,
                 band_material=belt, badge_material=brass, collar_material=coat_dark)
