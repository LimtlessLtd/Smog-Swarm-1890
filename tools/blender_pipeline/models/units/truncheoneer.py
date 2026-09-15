"""assets/units/truncheoneer_<facing>.png — GameEnums.UnitType.TRUNCHEONEER (Tier 0 Melee).

Tier 0 melee, the drabbest red on role_coat_color()'s ramp — a dirty brick against
the Highlander's near-scarlet Tier 3.

Silhouette: the WIDEST, ROUNDEST headgear on the foot roster (a custodian helmet,
radius 0.108 against a shako's 0.090) and a short truncheon raised forward-right
rather than a long weapon on the centre line. Wide head, stubby weapon — the
opposite of sharpshooter.py's small cap and long barrel.

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

TIER = 0
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
TRUNCHEON = (0.345, 0.224, 0.125)
CAPE = tuple(c * 0.86 for c in COAT)

GRIP = (0.235, 0.215, FIGURE_ARM_Z)
TIP = (0.320, 0.430, FIGURE_WEAPON_Z)


def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    coat_light = flat_material("CoatLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    wood = flat_material("Truncheon", TRUNCHEON)
    helmet = flat_material("Helmet", (0.290, 0.290, 0.320))

    soldier_boots(boot)
    # No knapsack at Tier 0 — a constable is not campaigning, and the missing
    # rear mass is itself a tier cue against the Tier 2 line infantry.
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=1.06)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=2, pouch=False,
                 cross_belts=False)
    # Single cross-belt only, so the chest reads plainer than a line soldier's X.
    part(bpy.ops.mesh.primitive_cube_add, belt, (0.0, 0.015, FIGURE_TORSO_TOP + 0.004),
         rotation=(0.0, 0.0, 0.72), scale=(0.034, 0.255, 0.012), size=1.0)

    soldier_arm(sleeve, coat_dark, skin, right_shoulder, GRIP, brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder,
                (-0.175, 0.185, FIGURE_ARM_Z), brass_material=brass)

    bone(wood, GRIP, TIP, 0.026)
    part(bpy.ops.mesh.primitive_uv_sphere_add, wood, TIP,
         segments=8, ring_count=5, radius=0.030)

    soldier_head(helmet, radius=0.108, height=0.125, peak=0.070,
                 band_material=belt, badge_material=brass, collar_material=coat_dark)
