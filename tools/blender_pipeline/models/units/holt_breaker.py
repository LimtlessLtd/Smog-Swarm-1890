"""assets/units/holt_breaker_<facing>.png — GameEnums.UnitType.HOLT_BREAKER (Tier 5 Melee, UnitAbility.TRAMPLE_KNOCKBACK).

Tier 5 melee. The heavier half of the ram pair: TRACKED where traction_ram.py is
wheeled, and its ram is a toothed plate rather than a plain blade. Widest hull on
the roster, so it reads as the heaviest thing the player fields.

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
    flat_material, part, bone, wheel, role_panel_color, ROLE_MELEE,
)

TIER = 5
PANEL = role_panel_color(ROLE_MELEE, TIER)
PANEL_DARK = tuple(c * 0.68 for c in PANEL)
HULL = (0.243, 0.231, 0.216)
HULL_LIGHT = (0.353, 0.341, 0.325)
TRACK = (0.118, 0.110, 0.102)
CLEAT = (0.196, 0.188, 0.180)
STEEL = (0.396, 0.412, 0.435)
STACK = (0.157, 0.149, 0.145)
BRASS = (0.796, 0.635, 0.259)


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
    brass = flat_material("Brass", BRASS)

    _tracks(track, cleat, 0.385, 0.600, count=8)

    part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, -0.040, 0.160),
         scale=(0.560, 1.000, 0.300), size=1.0)
    # Riveted deck plate, one tonal step up so the hull is not one flat field.
    part(bpy.ops.mesh.primitive_cube_add, hull_light, (0.0, -0.060, DECK_Z + 0.085),
         scale=(0.420, 0.720, 0.030), size=1.0)
    for sy in (-0.230, 0.020, 0.270):
        for sx in (-0.170, 0.170):
            part(bpy.ops.mesh.primitive_cylinder_add, steel, (sx, sy, DECK_Z + 0.105),
                 vertices=6, radius=0.022, depth=0.012)

    # Ram plate with teeth — the melee identity, in the role's red.
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, 0.580, 0.150),
         scale=(0.920, 0.160, 0.270), size=1.0)
    for i in range(5):
        part(bpy.ops.mesh.primitive_cone_add, panel_dark,
             (-0.320 + i * 0.160, 0.700, 0.150), rotation=(-1.5708, 0.0, 0.0),
             radius1=0.056, radius2=0.0, depth=0.140)

    # Engine louvre panel and exhaust stack at the rear.
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, -0.380, DECK_Z + 0.105),
         scale=(0.400, 0.230, 0.030), size=1.0)
    for i in range(4):
        part(bpy.ops.mesh.primitive_cube_add, panel_dark, (-0.135 + i * 0.090, -0.380, DECK_Z + 0.125),
             scale=(0.045, 0.200, 0.012), size=1.0)
    part(bpy.ops.mesh.primitive_cylinder_add, stack, (0.175, -0.150, DECK_Z + 0.150),
         vertices=12, radius=0.078, depth=0.200)
    part(bpy.ops.mesh.primitive_cylinder_add, brass, (0.175, -0.150, DECK_Z + 0.255),
         vertices=10, radius=0.088, depth=0.018)

    # Driver's cupola, off-centre so the vehicle is not bilaterally identical.
    part(bpy.ops.mesh.primitive_cylinder_add, hull_light, (-0.155, 0.150, DECK_Z + 0.135),
         vertices=12, radius=0.140, depth=0.110)
    part(bpy.ops.mesh.primitive_cube_add, steel, (-0.155, 0.260, DECK_Z + 0.150),
         scale=(0.120, 0.030, 0.050), size=1.0)
