"""assets/buildings/sulfur_mine.png — GameEnums.BuildingType.SULFUR_MINE.

Tier 3. Headframe plus a retort bank — a row of squat cylinders with bright
yellow mouths where the ore is cooked. Sulfur yellow is the most saturated ore
colour in the family and the retorts repeat it five times, so this site reads
yellow at any zoom that resolves it at all.

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

ORE_COLOR = (0.859, 0.749, 0.161)  # brimstone yellow

SHAFT_XY = (-0.24, 0.14)
RETORT_Y = -0.26


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    ore_mat = flat_material("Ore", ORE_COLOR)
    dirt_mat = flat_material("Dirt", (0.463, 0.408, 0.267), alpha=0.82)
    track_mat = flat_material("Track", (0.553, 0.494, 0.349), alpha=0.92)
    iron_mat = flat_material("Iron", (0.365, 0.353, 0.325))

    ground_patch(dirt_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.002), radius_x=0.40,
                 radius_y=0.36, seed=701, name="PitYard")
    ground_patch(dirt_mat, (0.10, RETORT_Y, 0.002), radius_x=0.52, radius_y=0.22,
                 sides=13, jitter=0.24, seed=709, name="RetortGround")

    path(track_mat, [SHAFT_XY, (-0.10, -0.06), (0.02, RETORT_Y + 0.12)],
         width=0.11, seed=719)

    headframe(timber_mat, shaft_mat, SHAFT_XY)

    # Retort bank: five squat cylinders in a line, each with a yellow mouth.
    for i in range(5):
        x = -0.30 + i * 0.20
        part(bpy.ops.mesh.primitive_cylinder_add, iron_mat, (x, RETORT_Y, 0.11),
             radius=0.085, depth=0.22)
        part(bpy.ops.mesh.primitive_cylinder_add, ore_mat, (x, RETORT_Y, 0.225),
             radius=0.048, depth=0.025)

    spoil_heaps(ore_mat, ((-0.46, 0.38), (-0.12, 0.44)), base_radius=0.14)
