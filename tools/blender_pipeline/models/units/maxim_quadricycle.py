"""assets/units/maxim_quadricycle_<facing>.png — GameEnums.UnitType.MAXIM_QUADRICYCLE (Tier 4 Ranged).

Tier 4 ranged. The LIGHTEST machine on the roster: an open four-wheeled frame
with a Maxim gun on a pintle, no armour and no hull to speak of. Four separate
wheel discs with visible gaps between them make it the only unit whose outline is
mostly HOLES, which is what separates it from the armoured boxes at the same
tiers.

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

TIER = 4
PANEL = role_panel_color(ROLE_RANGED, TIER)
PANEL_DARK = tuple(c * 0.68 for c in PANEL)
HULL = (0.243, 0.231, 0.216)
HULL_LIGHT = (0.353, 0.341, 0.325)
TRACK = (0.118, 0.110, 0.102)
CLEAT = (0.196, 0.188, 0.180)
STEEL = (0.396, 0.412, 0.435)
STACK = (0.157, 0.149, 0.145)
BRASS = (0.796, 0.635, 0.259)
WHEEL_C = (0.169, 0.161, 0.153)
WATER = (0.376, 0.400, 0.427)

DECK_Z = 0.22   # hull top; everything mounted on the vehicle sits above this


def build():
    panel = flat_material("Panel", PANEL)
    panel_dark = flat_material("PanelDark", PANEL_DARK)
    hull = flat_material("Hull", HULL)
    steel = flat_material("Steel", STEEL)
    brass = flat_material("Brass", BRASS)
    wheel_mat = flat_material("Wheel", WHEEL_C)
    water = flat_material("Jacket", WATER)

    for sx in (-1.0, 1.0):
        for sy, radius in ((-1.0, 0.170), (1.0, 0.150)):
            part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat,
                 (sx * 0.285, sy * 0.290, radius * 0.62),
                 rotation=(0.0, 1.5708, 0.0), vertices=12, radius=radius, depth=0.062)

    # Open frame: two rails and two cross members, deliberately not a slab.
    for sx in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cube_add, hull, (sx * 0.215, 0.0, 0.135),
             scale=(0.055, 0.640, 0.055), size=1.0)
    for sy in (-1.0, 1.0):
        part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, sy * 0.225, 0.135),
             scale=(0.430, 0.055, 0.055), size=1.0)

    # Gunner's seat and the pintle.
    part(bpy.ops.mesh.primitive_uv_sphere_add, panel, (0.0, -0.170, 0.190),
         scale=(0.130, 0.105, 0.045), segments=12, ring_count=7, radius=1.0)
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.0, 0.055, 0.185),
         vertices=10, radius=0.055, depth=0.110)

    # Maxim: water jacket, barrel, and the ammunition belt feeding in from the
    # side — the belt is this unit's signature, no other weapon has one.
    part(bpy.ops.mesh.primitive_cylinder_add, water, (0.0, 0.255, 0.255),
         rotation=(1.5708, 0.0, 0.0), vertices=12, radius=0.060, depth=0.290)
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.0, 0.470, 0.255),
         rotation=(1.5708, 0.0, 0.0), vertices=8, radius=0.020, depth=0.150)
    part(bpy.ops.mesh.primitive_cube_add, panel, (-0.130, 0.130, 0.250),
         rotation=(0.0, 0.0, 0.38), scale=(0.170, 0.055, 0.030), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, brass, (-0.195, 0.090, 0.255),
         scale=(0.095, 0.075, 0.035), size=1.0)
