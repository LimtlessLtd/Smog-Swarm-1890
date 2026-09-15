"""assets/units/highlander_<facing>.png — GameEnums.UnitType.HIGHLANDER (Tier 3 Melee).

Tier 3 melee, the brightest red on the ramp.

Silhouette: the only unit carrying a SHIELD — a round targe on the left arm,
which from overhead is a hard bright disc offset from the body, and the single
most distinctive thing any foot figure has. Plus a feather bonnet, the largest
headgear on the roster (radius 0.125 of soft mass), and a broadsword raised on
the right. Shield left, sword right, huge head: unmistakable.

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
    soldier_pack, FIGURE_Z, FIGURE_ARM_Z, FIGURE_TRIM_Z, FIGURE_TORSO_TOP,
    FIGURE_WEAPON_Z,
)

TIER = 3
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
BONNET = (0.180, 0.173, 0.161)
TARGE = (0.451, 0.298, 0.161)
BLADE = (0.647, 0.667, 0.694)
TARTAN = (0.412, 0.176, 0.153)

SWORD_GRIP = (0.240, 0.135, FIGURE_ARM_Z)
SWORD_TIP = (0.330, 0.470, FIGURE_WEAPON_Z)
TARGE_AT = (-0.250, 0.115, FIGURE_ARM_Z)


def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    coat_light = flat_material("CoatLight", COAT_LIGHT)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    boot = flat_material("Boot", BOOT)
    brass = flat_material("Brass", BRASS)
    bonnet = flat_material("Bonnet", BONNET)
    targe = flat_material("Targe", TARGE)
    blade = flat_material("Blade", BLADE)
    tartan = flat_material("Tartan", TARTAN)

    soldier_boots(boot, spread=0.120)
    left_shoulder, right_shoulder = soldier_torso(coat, bulk=1.04)
    # Kilt: a wider skirt below the coat, in a second red, so the lower body is
    # broader than any other foot unit's.
    part(bpy.ops.mesh.primitive_uv_sphere_add, tartan, (0.0, -0.115, FIGURE_Z - 0.020),
         scale=(0.185, 0.115, 0.085), segments=14, ring_count=8, radius=1.0)
    soldier_trim(coat_light, coat_dark, belt, brass, buttons=2, waist_belt=True,
                 pouch=False)
    # Sporran, centred on the kilt.
    part(bpy.ops.mesh.primitive_uv_sphere_add, belt, (0.0, -0.140, FIGURE_TRIM_Z + 0.006),
         scale=(0.055, 0.045, 0.016), segments=10, ring_count=6, radius=1.0)

    soldier_arm(sleeve, coat_dark, skin, right_shoulder, SWORD_GRIP, elbow_out=0.085,
                brass_material=brass)
    soldier_arm(sleeve, coat_dark, skin, left_shoulder, TARGE_AT, elbow_out=0.060)

    # Targe: disc, rim and boss — the roster's only shield.
    part(bpy.ops.mesh.primitive_cylinder_add, targe, (TARGE_AT[0], TARGE_AT[1], FIGURE_WEAPON_Z),
         vertices=16, radius=0.135, depth=0.030)
    part(bpy.ops.mesh.primitive_torus_add, brass, (TARGE_AT[0], TARGE_AT[1], FIGURE_WEAPON_Z + 0.018),
         major_radius=0.112, minor_radius=0.014)
    part(bpy.ops.mesh.primitive_cylinder_add, brass, (TARGE_AT[0], TARGE_AT[1], FIGURE_WEAPON_Z + 0.022),
         vertices=10, radius=0.034, depth=0.014)

    # Broadsword with a basket hilt.
    bone(blade, SWORD_GRIP, SWORD_TIP, 0.018)
    part(bpy.ops.mesh.primitive_uv_sphere_add, brass, SWORD_GRIP,
         scale=(0.052, 0.052, 0.024), segments=10, ring_count=6, radius=1.0)

    # Feather bonnet: a big soft mass, no peak, with a plume to one side.
    soldier_head(bonnet, radius=0.125, height=0.105, peak=None,
                 collar_material=coat_dark)
    part(bpy.ops.mesh.primitive_uv_sphere_add, bonnet, (-0.045, 0.145, FIGURE_ARM_Z + 0.175),
         scale=(0.062, 0.062, 0.040), segments=10, ring_count=6, radius=1.0)
