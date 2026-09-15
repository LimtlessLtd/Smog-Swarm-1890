"""assets/units/armoured_command_car_<facing>.png — GameEnums.UnitType.ARMOURED_COMMAND_CAR (Tier 5 Special, UnitAbility.RAPID_RESPONSE).

Tier 5 special — fast and lightly armed rather than a heavy hitter (UnitCatalog).

Silhouette: a SLEEK wheeled hull, narrower and more pointed than any other
vehicle, with a small turret and a tall aerial array. The aerial is the mark: a
mast with cross spars, the only vertical fretwork on the roster, and it says
"command" where every other Tier 5 says "weapon".

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
    flat_material, part, bone, wheel, role_panel_color, ROLE_SPECIAL,
)

TIER = 5
PANEL = role_panel_color(ROLE_SPECIAL, TIER)
PANEL_DARK = tuple(c * 0.68 for c in PANEL)
HULL = (0.243, 0.231, 0.216)
HULL_LIGHT = (0.353, 0.341, 0.325)
TRACK = (0.118, 0.110, 0.102)
CLEAT = (0.196, 0.188, 0.180)
STEEL = (0.396, 0.412, 0.435)
STACK = (0.157, 0.149, 0.145)
BRASS = (0.796, 0.635, 0.259)
WHEEL_C = (0.169, 0.161, 0.153)
AERIAL = (0.478, 0.494, 0.522)

DECK_Z = 0.22   # hull top; everything mounted on the vehicle sits above this


def build():
    panel = flat_material("Panel", PANEL)
    panel_dark = flat_material("PanelDark", PANEL_DARK)
    hull = flat_material("Hull", HULL)
    hull_light = flat_material("HullLight", HULL_LIGHT)
    steel = flat_material("Steel", STEEL)
    brass = flat_material("Brass", BRASS)
    wheel_mat = flat_material("Wheel", WHEEL_C)
    aerial = flat_material("Aerial", AERIAL)

    for sx in (-1.0, 1.0):
        for sy in (-0.330, 0.330):
            part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat, (sx * 0.290, sy, 0.120),
                 rotation=(0.0, 1.5708, 0.0), vertices=14, radius=0.165, depth=0.085)

    # Hull: tapered to a prow at the front, so it reads as fast.
    part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, -0.040, 0.165),
         scale=(0.430, 0.820, 0.300), size=1.0)
    part(bpy.ops.mesh.primitive_cone_add, hull, (0.0, 0.480, 0.165),
         rotation=(-1.5708, 0.0, 0.0), vertices=4, radius1=0.305, radius2=0.0, depth=0.300)
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, 0.055, DECK_Z + 0.100),
         scale=(0.330, 0.520, 0.030), size=1.0)

    # Turret with a short barrel.
    part(bpy.ops.mesh.primitive_cylinder_add, hull_light, (0.0, 0.010, DECK_Z + 0.150),
         vertices=12, radius=0.175, depth=0.130)
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.0, 0.230, DECK_Z + 0.155),
         rotation=(1.5708, 0.0, 0.0), vertices=8, radius=0.030, depth=0.260)

    # Aerial array on the rear deck — mast plus three cross spars.
    part(bpy.ops.mesh.primitive_cylinder_add, aerial, (0.0, -0.330, DECK_Z + 0.190),
         vertices=8, radius=0.020, depth=0.240)
    for i, span in enumerate((0.300, 0.230, 0.160)):
        part(bpy.ops.mesh.primitive_cube_add, aerial, (0.0, -0.330, DECK_Z + 0.240 + i * 0.045),
             scale=(span, 0.018, 0.012), size=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, brass, (0.0, -0.330, DECK_Z + 0.320),
         segments=8, ring_count=5, radius=0.036)
