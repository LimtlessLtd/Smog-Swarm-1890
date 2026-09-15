"""assets/buildings/deep_coal_shafts.png — GameEnums.BuildingType.DEEP_COAL_SHAFTS.

Tier 3 high-output Coal consolidator. Deliberately coal_pithead's site with TWO
headframes instead of one, bigger heaps, and a tramway running between the shafts.
The roster says this is "more colliery", so the art says the same rather than
inventing an unrelated building: reading it against a Tier 1 pithead should feel
like a bigger version of the same place.

Re-authored 2026-09-15 for the straight-down camera, on the extraction family's
ground/path system (see coal_pithead.py for the reference model, and
render_common's organic-ground block for why the old full-quad plate went).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, headframe, spoil_heaps, ground_patch, path,
    family_materials,
)

ORE_COLOR = (0.105, 0.098, 0.094)  # coal

SHAFT_A = (-0.30, 0.18)
SHAFT_B = (0.22, 0.24)
ENGINE_XY = (0.42, -0.14)


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    ore_mat = flat_material("Ore", ORE_COLOR)
    dirt_mat = flat_material("Dirt", (0.376, 0.318, 0.224), alpha=0.84)
    track_mat = flat_material("Track", (0.290, 0.243, 0.176), alpha=0.92)

    for i, xy in enumerate((SHAFT_A, SHAFT_B)):
        ground_patch(dirt_mat, (xy[0], xy[1], 0.002), radius_x=0.36, radius_y=0.34,
                     seed=801 + i * 11, name="PitYard%d" % i)
    ground_patch(dirt_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.002), radius_x=0.28,
                 radius_y=0.26, seed=821, name="EngineYard")

    # Tramway linking both shafts to the winding house — "more of the same",
    # made literal.
    path(track_mat, [SHAFT_A, (-0.04, 0.22), SHAFT_B], width=0.12, seed=829)
    path(track_mat, [SHAFT_B, (0.34, 0.06), ENGINE_XY], width=0.11, seed=833)

    headframe(timber_mat, shaft_mat, SHAFT_A, shaft_half=0.15, wheel_outer=0.20)
    headframe(timber_mat, shaft_mat, SHAFT_B, shaft_half=0.13, wheel_outer=0.18)

    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.08),
         scale=(0.28, 0.32, 0.14), size=1.0)
    hip_roof(timber_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.15), width=0.26, depth=0.30,
             height=0.13, ridge_fraction=0.55)

    spoil_heaps(ore_mat, ((-0.44, -0.34), (-0.12, -0.44), (0.16, -0.40)), base_radius=0.18)
