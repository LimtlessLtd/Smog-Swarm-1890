"""assets/units/field_howitzer_gun_tractor_<facing>.png — GameEnums.UnitType.FIELD_HOWITZER_GUN_TRACTOR (Tier 5 Ranged).

Tier 5 ranged. A tractor with a howitzer limbered behind it, so the outline is
TWO masses joined by a drawbar — the only articulated vehicle on the roster, and
the longest. The gun's split trail and big shield make the rear mass read as
artillery rather than as a trailer.

Tiers 4-5 are machines, so there is no coat to carry the role hue —
the role hue goes onto HULL PANELS instead, via role_panel_color() — the coat
ramp knocked back toward the hull grey, because a painted steel panel is a
muted version of a dress-uniform colour rather than the same colour. That keeps
a Tier 5 melee vehicle in the same red family as a Tier 0 Truncheoneer while
being obviously a different class of thing. Vehicles are also the only strictly RECTILINEAR
outlines on the unit roster, where every figure is round and every horse is a
long oval, so "machine" reads before anything else does.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, bone, wheel, role_panel_color, ROLE_RANGED,
)

TIER = 5
PANEL = role_panel_color(ROLE_RANGED, TIER)
PANEL_DARK = tuple(c * 0.68 for c in PANEL)
HULL = (0.243, 0.231, 0.216)
HULL_LIGHT = (0.353, 0.341, 0.325)
TRACK = (0.118, 0.110, 0.102)
CLEAT = (0.196, 0.188, 0.180)
STEEL = (0.396, 0.412, 0.435)
STACK = (0.157, 0.149, 0.145)
BRASS = (0.796, 0.635, 0.259)
SHIELD = (0.333, 0.353, 0.322)

DECK_Z = 0.22   # hull top; everything mounted on the vehicle sits above this

def _tracks(track_mat, cleat_mat, half_width, half_length, count=7):
    """Two track runs with cleat bars across them. The cleats are what make a
    dark rectangle read as a track rather than as a painted stripe — without
    them a tracked vehicle and a flatbed look identical from overhead."""
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cube_add, track_mat,
             (side * half_width, 0.0, 0.11), scale=(0.105, half_length, 0.20), size=1.0)
        for i in range(count):
            y = -half_length * 0.86 + (2.0 * half_length * 0.86) * i / (count - 1)
            part(bpy.ops.mesh.primitive_cube_add, cleat_mat,
                 (side * half_width, y, 0.215), scale=(0.115, 0.038, 0.016), size=1.0)

def build():
    panel = flat_material("Panel", PANEL)
    panel_dark = flat_material("PanelDark", PANEL_DARK)
    hull = flat_material("Hull", HULL)
    hull_light = flat_material("HullLight", HULL_LIGHT)
    track = flat_material("Track", TRACK)
    cleat = flat_material("Cleat", CLEAT)
    steel = flat_material("Steel", STEEL)
    stack = flat_material("Stack", STACK)
    shield = flat_material("Shield", SHIELD)

    _tracks(track, cleat, 0.300, 0.400, count=6)

    # Tractor, forward mass.
    part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, 0.230, 0.155),
         scale=(0.430, 0.640, 0.290), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, hull_light, (0.0, 0.330, DECK_Z + 0.085),
         scale=(0.330, 0.330, 0.030), size=1.0)
    part(bpy.ops.mesh.primitive_cylinder_add, stack, (0.145, 0.470, DECK_Z + 0.135),
         vertices=12, radius=0.068, depth=0.180)
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, 0.055, DECK_Z + 0.090),
         scale=(0.340, 0.180, 0.030), size=1.0)

    # Drawbar: the join that makes this unit articulated.
    bone(steel, (0.0, -0.075, 0.150), (0.0, -0.290, 0.150), 0.036)

    # Howitzer: wheels, shield, split trail, barrel over the top.
    for sx in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cylinder_add, steel, (sx * 0.290, -0.440, 0.150),
             rotation=(0.0, 1.5708, 0.0), vertices=14, radius=0.190, depth=0.070)
    part(bpy.ops.mesh.primitive_cube_add, shield, (0.0, -0.335, 0.190),
         scale=(0.560, 0.055, 0.320), size=1.0)
    for sx in (-1.0, 1.0):
        bone(hull, (sx * 0.075, -0.470, 0.115), (sx * 0.230, -0.760, 0.115), 0.034)
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.0, -0.300, 0.265),
         rotation=(1.5708, 0.0, 0.0), vertices=12, radius=0.058, depth=0.560)
    part(bpy.ops.mesh.primitive_cylinder_add, panel_dark, (0.0, -0.035, 0.265),
         rotation=(1.5708, 0.0, 0.0), vertices=12, radius=0.072, depth=0.080)
