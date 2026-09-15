"""assets/units/searchlight_tender_<facing>.png — GameEnums.UnitType.SEARCHLIGHT_TENDER (Tier 4 Special, UnitAbility.MOBILE_SUPPLY_DUMP).

Tier 4 special — projects a Military ZoC/resupply aura wherever it stands and
doubles as a moving vision source (LogisticsNetwork.recompute()).

Silhouette: the only unit carrying a large PALE DISC — the searchlight lens, the
brightest single shape on the whole roster, deliberately echoing
searchlight_tower.py so the mobile and static versions read as the same
equipment. A generator box and cable drum sit behind it.

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

TIER = 4
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
LENS = (0.937, 0.918, 0.804)

DECK_Z = 0.22   # hull top; everything mounted on the vehicle sits above this


def build():
    panel = flat_material("Panel", PANEL)
    panel_dark = flat_material("PanelDark", PANEL_DARK)
    hull = flat_material("Hull", HULL)
    hull_light = flat_material("HullLight", HULL_LIGHT)
    steel = flat_material("Steel", STEEL)
    brass = flat_material("Brass", BRASS)
    wheel_mat = flat_material("Wheel", WHEEL_C)
    lens = flat_material("Lens", LENS)

    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            part(bpy.ops.mesh.primitive_cylinder_add, wheel_mat,
                 (sx * 0.300, sy * 0.290, 0.105),
                 rotation=(0.0, 1.5708, 0.0), vertices=12, radius=0.150, depth=0.075)

    part(bpy.ops.mesh.primitive_cube_add, hull, (0.0, -0.030, 0.135),
         scale=(0.450, 0.720, 0.250), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, panel, (0.0, -0.250, DECK_Z + 0.040),
         scale=(0.330, 0.200, 0.030), size=1.0)

    # Generator and cable drum on the rear deck.
    part(bpy.ops.mesh.primitive_cube_add, hull_light, (-0.105, -0.140, DECK_Z + 0.075),
         scale=(0.180, 0.180, 0.100), size=1.0)
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.135, -0.150, DECK_Z + 0.075),
         vertices=12, radius=0.090, depth=0.100)

    # The light: a drum with a big pale lens, on a turntable.
    part(bpy.ops.mesh.primitive_cylinder_add, steel, (0.0, 0.180, DECK_Z + 0.045),
         vertices=12, radius=0.115, depth=0.060)
    part(bpy.ops.mesh.primitive_cylinder_add, hull_light, (0.0, 0.215, DECK_Z + 0.135),
         vertices=16, radius=0.235, depth=0.130)
    part(bpy.ops.mesh.primitive_cylinder_add, lens, (0.0, 0.215, DECK_Z + 0.205),
         vertices=16, radius=0.190, depth=0.030)
    part(bpy.ops.mesh.primitive_torus_add, brass, (0.0, 0.215, DECK_Z + 0.210),
         major_radius=0.205, minor_radius=0.020)
