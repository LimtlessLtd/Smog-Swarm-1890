"""assets/buildings/iron_ore_mine.png — GameEnums.BuildingType.IRON_ORE_MINE.

One headframe, rust-red heaps, and a row of ore bins over a loading dock — the
family member that looks like it SHIPS its output, against sulfur_mine's retorts
(which cook it) and deep_coal_shafts' second headframe (which just does more of
the same).

Re-authored 2026-09-15 for the straight-down camera, on the extraction family's
ground/path system (see coal_pithead.py for the reference model, and
render_common's organic-ground block for why the old full-quad plate went).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, headframe, spoil_heaps, ground_patch, path,
    family_materials,
)

ORE_COLOR = (0.545, 0.243, 0.133)  # haematite rust

SHAFT_XY = (-0.20, 0.16)
DOCK_XY = (0.34, -0.20)


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    ore_mat = flat_material("Ore", ORE_COLOR)
    dirt_mat = flat_material("Dirt", (0.451, 0.345, 0.267), alpha=0.82)
    track_mat = flat_material("Track", (0.545, 0.443, 0.345), alpha=0.92)

    ground_patch(dirt_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.002), radius_x=0.40,
                 radius_y=0.38, seed=601, name="PitYard")
    ground_patch(dirt_mat, (DOCK_XY[0], DOCK_XY[1], 0.002), radius_x=0.34,
                 radius_y=0.24, sides=11, jitter=0.26, seed=613, name="DockGround")

    path(track_mat, [SHAFT_XY, (0.02, -0.02), DOCK_XY], width=0.12, seed=617)

    headframe(timber_mat, shaft_mat, SHAFT_XY)

    # Ore bins: four hoppers in a row over the dock, each a square with a dark
    # chute mouth. The row is this mine's own rhythm.
    for i in range(4):
        x = DOCK_XY[0] - 0.18 + i * 0.12
        part(bpy.ops.mesh.primitive_cube_add, timber_mat, (x, DOCK_XY[1], 0.10),
             scale=(0.10, 0.20, 0.20), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, shaft_mat, (x, DOCK_XY[1] - 0.06, 0.205),
             scale=(0.055, 0.055, 0.02), size=1.0)

    spoil_heaps(ore_mat, ((-0.46, -0.30), (-0.16, -0.40), (0.06, -0.44)), base_radius=0.15)
