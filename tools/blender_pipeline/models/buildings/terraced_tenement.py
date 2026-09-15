"""assets/buildings/terraced_tenement.png — GameEnums.BuildingType.WOODEN_HOUSES
(BuildingVisuals._texture_key keeps the pre-rework art key).

Re-authored 2026-09-15 for the straight-down camera. This model was the worst
case measured: overhead, the old angled terrace rendered as four plain brown
rectangles in a row with no interior detail at all. The housing family signature
is a ROW of parallel hip roofs with paired chimneys per bay — from above that is
a run of ridge lines and a regular grid of chimney discs, which is exactly what a
terrace looks like from the air and nothing else on the roster does.

Ground follows the user's note about squares and paths: a cobbled street runs
along the front of the terrace and a back lane along the rear, with each bay's
own yard as a separate worn patch between them. The lane is the "path between the
various different buildings within 1 asset" in its most literal form, and the
gaps between yards let terrain through.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ground_patch, path, family_materials,
)

BAY_COUNT = 4
BAY_WIDTH = 0.26
ROW_Y = 0.10


def build():
    cobble_mat, roof_mat, chimney_mat = family_materials("housing")
    dirt_mat = flat_material("Dirt", (0.376, 0.353, 0.318), alpha=0.78)
    street_mat = flat_material("Street", (0.463, 0.451, 0.435), alpha=0.92)

    span = BAY_COUNT * BAY_WIDTH
    start = -(span - BAY_WIDTH) / 2.0

    # One worn yard per bay, not one slab for the terrace. Touching but not
    # concentric, so the rear edge of the site is a run of scallops.
    for i in range(BAY_COUNT):
        x = start + i * BAY_WIDTH
        ground_patch(dirt_mat, (x, -0.26, 0.002), radius_x=0.17, radius_y=0.16,
                     sides=11, jitter=0.26, seed=61 + i * 13, name="Yard%d" % i)

    # Cobbled street along the front and a back lane behind the yards. Both run
    # off the frame edge so the terrace reads as part of a longer street.
    path(street_mat, [(-0.72, 0.36), (-0.20, 0.38), (0.24, 0.37), (0.72, 0.39)],
         width=0.17, seed=7, name="Street")
    path(street_mat, [(-0.70, -0.42), (-0.10, -0.44), (0.70, -0.42)],
         width=0.11, seed=13, name="BackLane")
    # Entries from the street to each front door.
    for i in range(BAY_COUNT):
        x = start + i * BAY_WIDTH
        path(street_mat, [(x, 0.34), (x, 0.28)], width=0.07, seed=71 + i, name="Entry%d" % i)

    for i in range(BAY_COUNT):
        x = start + i * BAY_WIDTH
        # Each bay is its own hipped roof rather than one long roof split by
        # lines: separate roofs give Freestyle a real party-wall edge between
        # bays, so the terrace still reads as N dwellings when minified.
        part(bpy.ops.mesh.primitive_cube_add, cobble_mat, (x, ROW_Y, 0.08),
             scale=(BAY_WIDTH - 0.01, 0.40, 0.14), size=1.0)
        hip_roof(roof_mat, (x, ROW_Y, 0.15), width=BAY_WIDTH - 0.02, depth=0.38,
                 height=0.15, ridge_fraction=0.34, name="Bay%d" % i)
        for y in (ROW_Y - 0.13, ROW_Y + 0.13):
            roof_vent(chimney_mat, (x, y, 0.27), radius=0.030, height=0.09)

    # Privy blocks along the back of each yard — small squares in a line, the
    # detail that says "terrace" rather than "warehouse".
    for i in range(BAY_COUNT):
        x = start + i * BAY_WIDTH
        part(bpy.ops.mesh.primitive_cube_add, roof_mat, (x, -0.30, 0.06),
             scale=(0.09, 0.09, 0.11), size=1.0)
