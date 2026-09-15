"""assets/units/traction_ram_<facing>.png — GameEnums.UnitType.TRACTION_RAM (Tier 4 Melee, UnitAbility.TRAMPLE_KNOCKBACK).

Tier 4 melee. The SMALLER of the two ram vehicles: a traction engine with a
plough blade bolted on, big rear driving wheels and a tall chimney. Against
holt_breaker.py (Tier 5, tracked, toothed ram) this one is wheeled and has a
plain curved blade, so the pair reads as the same idea at two levels of
industrialisation rather than as two unrelated machines.

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

TIER = 4
PANEL = role_panel_color(ROLE_MELEE, TIER)
PANEL_DARK = tuple(c * 0.68 for c in PANEL)
HULL = (0.243, 0.231, 0.216)
HULL_LIGHT = (0.353, 0.341, 0.325)
TRACK = (0.118, 0.110, 0.102)
CLEAT = (0.196, 0.188, 0.180)
STEEL = (0.396, 0.412, 0.435)
STACK = (0.157, 0.149, 0.145)
BRASS = (0.796, 0.635, 0.259)
WHEEL_C = (0.180, 0.169, 0.157)

DECK_Z = 0.22   # hull top; everything mounted on the vehicle sits above this


def build():
    panel = flat_material("Panel", PANEL)
    panel_dark = flat_material("PanelDark", PANEL_DARK)
    hull = flat_material("Hull", HULL)
    hull_light = flat_material("HullLight", HULL_LIGHT)
    steel = flat_material("Steel", STEEL)
    stack = flat_material("Stack", STACK)
    brass = flat_material("Brass", BRASS)
    wheel_mat = flat_material("Wheel", WHEEL_C)

    # Big rear driving wheels and small front steering wheels — a traction
    # engine's own proportion, and unlike any tracked unit.
    for side in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat, (side * 0.315, -0.185, 0.145),
             rotation=(0.0, 1.5708, 0.0), vertices=14, radius=0.225, depth=0.105)
        part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat, (side * 0.255, 0.225, 0.105),
             rotation=(0.0, 1.5708, 0.0), vertices=12, radius=0.130, depth=0.080)

    part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, -0.030, 0.145),
         scale=(0.430, 0.760, 0.270), size=1.0)
    # Boiler barrel running forward along the hull.
    part(bpy.ops.mesh.primitive_cylinder_add, hull_light, (0.0, 0.135, DECK_Z + 0.065),
         rotation=(1.5708, 0.0, 0.0), vertices=14, radius=0.125, depth=0.420)
    part(bpy.ops.mesh.primitive_cylinder_add, stack, (0.0, 0.310, DECK_Z + 0.130),
         vertices=12, radius=0.072, depth=0.190)
    part(bpy.ops.mesh.primitive_cylinder_add, brass, (0.0, 0.310, DECK_Z + 0.230),
         vertices=10, radius=0.082, depth=0.020)

    # Plough blade: a plain curve, no teeth.
    part(bpy.ops.mesh.primitive_cylinder_add, panel, (0.0, 0.460, 0.140),
         rotation=(1.5708, 0.0, 0.0), scale=(1.0, 0.45, 1.0),
         vertices=16, radius=0.235, depth=0.075)
    part(bpy.ops.mesh.primitive_cube_add, panel_dark, (0.0, 0.395, 0.145),
         scale=(0.300, 0.060, 0.170), size=1.0)

    # Driver's platform and canopy posts at the rear.
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, -0.300, DECK_Z + 0.055),
         scale=(0.290, 0.160, 0.030), size=1.0)
    for sx in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cylinder_add, steel, (sx * 0.135, -0.300, DECK_Z + 0.110),
             vertices=8, radius=0.022, depth=0.090)
