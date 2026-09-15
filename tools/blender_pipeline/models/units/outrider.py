"""assets/units/outrider_<facing>.png — GameEnums.UnitType.OUTRIDER (Tier 0 Special, UnitAbility.UNARMED_SCOUT).

Tier 0 scout, and the one unit on the roster that CANNOT fight — near-zero
attack_damage, pure vision and mobility (UnitCatalog).

So it is drawn unarmed, and that is the silhouette: nothing projects forward
except a raised spyglass. Lightest, smallest mount of the three cavalry, a tan
horse with no armour and no saddle furniture, and the drabbest purple on the
ramp. Against chasseur.py's carbine and dragoon.py's lance, "empty-handed" is
the read.

Mounted units share one silhouette advantage over every foot figure: a horse is
LONG front-to-back where a man is round, so the footprint alone separates cavalry
from infantry at any zoom that resolves more than a blob. They are then separated
from EACH OTHER by mount colour, rider kit and what projects forward.

Built on render_common's soldier rig for the rider; the horse is local to each
script because the three mounts differ in build.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, bone, limb, hand, role_coat_color, ROLE_SPECIAL,
    FIGURE_Z, FIGURE_ARM_Z, FIGURE_WEAPON_Z,
)

TIER = 0
COAT = role_coat_color(ROLE_SPECIAL, TIER)
COAT_DARK = tuple(c * 0.70 for c in COAT)
SLEEVE = tuple(c * 0.80 for c in COAT)
SKIN = (0.769, 0.600, 0.486)
BELT = (0.878, 0.851, 0.780)
BRASS = (0.796, 0.635, 0.259)
HORSE = (0.588, 0.451, 0.290)
HORSE_DARK = (0.376, 0.278, 0.176)
GLASS = (0.451, 0.478, 0.502)

# The rider sits above the horse, so every rider element is lifted clear of it.
RIDER_Z = FIGURE_Z + 0.135
RIDER_ARM_Z = RIDER_Z + 0.095


def _horse(body_mat, dark_mat, *, scale=1.0, tail=True):
    """Body, hindquarters, neck, head and four hooves along +Y.

    Drawn as overlapping domes rather than one ellipsoid so the barrel,
    hindquarters and neck read as separate masses from overhead — a single
    ellipsoid is the "amoeba" shape the first figure pass was rejected for.

    Numbers are HALF-EXTENTS (part() passes scale with radius=1.0), which is the
    trap the first version fell into: authored as if they were diameters, the
    body came out 1.1 x 1.2 units against a 0.35-wide rider and the horse
    swallowed the whole figure. A horse here is ~0.35 across and ~1.0 long, so
    roughly 3:1, which is what makes cavalry read as long where infantry is
    round.
    """
    w = 0.175 * scale
    part(bpy.ops.mesh.primitive_uv_sphere_add, body_mat, (0.0, 0.02, FIGURE_Z),
         scale=(w, 0.315 * scale, 0.105), segments=16, ring_count=9, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, body_mat, (0.0, -0.275 * scale, FIGURE_Z - 0.008),
         scale=(w * 0.94, 0.150 * scale, 0.098), segments=14, ring_count=8, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, body_mat, (0.0, 0.320 * scale, FIGURE_Z + 0.014),
         scale=(w * 0.62, 0.165 * scale, 0.086), segments=14, ring_count=8, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, dark_mat, (0.0, 0.495 * scale, FIGURE_Z + 0.006),
         scale=(w * 0.44, 0.105 * scale, 0.068), segments=12, ring_count=7, radius=1.0)
    for sx, sy in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        part(bpy.ops.mesh.primitive_cylinder_add, dark_mat,
             (sx * w * 0.74, sy * 0.225 * scale, 0.055), vertices=8,
             radius=0.038, depth=0.11)
    if tail:
        bone(dark_mat, (0.0, -0.400 * scale, FIGURE_Z - 0.015),
             (0.0, -0.545 * scale, FIGURE_Z - 0.045), 0.028)


def _rider(coat_mat, sleeve_mat, dark_mat, skin_mat, left_hand, right_hand):
    """Rider torso, arms and hands. Narrower than a foot figure's so the horse
    keeps ownership of the outline."""
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_mat, (0.0, -0.015, RIDER_Z),
         scale=(0.175, 0.115, 0.090), segments=16, ring_count=8, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_mat, (0.0, 0.055, RIDER_Z),
         scale=(0.120, 0.115, 0.086), segments=14, ring_count=8, radius=1.0)
    for side, target in ((-1.0, left_hand), (1.0, right_hand)):
        shoulder = (side * 0.165, -0.010, RIDER_ARM_Z)
        mid = ((shoulder[0] + target[0]) / 2.0, (shoulder[1] + target[1]) / 2.0, RIDER_ARM_Z)
        elbow = (mid[0] + side * 0.060, mid[1] + 0.070, RIDER_ARM_Z)
        limb(sleeve_mat, [shoulder, elbow, target], [0.042, 0.036])
        hand(skin_mat, target, radius=0.035)

def build():
    coat = flat_material("Coat", COAT)
    coat_dark = flat_material("CoatDark", COAT_DARK)
    sleeve = flat_material("Sleeve", SLEEVE)
    skin = flat_material("Skin", SKIN)
    belt = flat_material("Belt", BELT)
    brass = flat_material("Brass", BRASS)
    horse = flat_material("Horse", HORSE)
    horse_dark = flat_material("HorseDark", HORSE_DARK)
    glass = flat_material("Glass", GLASS)

    _horse(horse, horse_dark, scale=0.92)
    part(bpy.ops.mesh.primitive_uv_sphere_add, coat_dark, (0.0, -0.02, FIGURE_Z + 0.16),
         scale=(0.150, 0.125, 0.030), segments=14, ring_count=8, radius=1.0)

    right_hand = (0.175, 0.185, RIDER_ARM_Z)
    _rider(coat, sleeve, coat_dark, skin, (-0.150, 0.130, RIDER_ARM_Z), right_hand)

    # Spyglass raised to the eye — short, and the only thing this unit carries.
    bone(glass, right_hand, (0.135, 0.330, RIDER_ARM_Z + 0.02), 0.019)
    part(bpy.ops.mesh.primitive_cylinder_add, brass, (0.135, 0.330, RIDER_ARM_Z + 0.02),
         rotation=(1.5708, 0.0, 0.25), vertices=8, radius=0.024, depth=0.020)

    # Soft forage cap, low and small.
    part(bpy.ops.mesh.primitive_cylinder_add, coat_dark, (0.0, 0.095, RIDER_ARM_Z + 0.085),
         vertices=12, radius=0.074, depth=0.060)
    part(bpy.ops.mesh.primitive_cube_add, coat_dark, (0.0, 0.165, RIDER_ARM_Z + 0.070),
         scale=(0.110, 0.062, 0.014), size=1.0)
