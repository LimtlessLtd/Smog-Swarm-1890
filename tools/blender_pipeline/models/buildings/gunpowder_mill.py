"""assets/buildings/gunpowder_mill.png — GameEnums.BuildingType.GUNPOWDER_MILL.

BuildingVisuals._texture_key keeps the "saltpetre_powder_mill" art key. The
family's DISPERSED site: small blast-separated buildings each inside its own
earth traverse, spaced wide apart with covered ways between them, because a powder
mill that groups its buildings does not stay a powder mill. Wide spacing plus
small huts is the opposite of every other heavy building's dense cluster, and it
is the one place the transparent gaps between patches are doing narrative work.

Re-authored 2026-09-15 for the straight-down camera. Heavy industry shares one
palette across eleven buildings (render_common.BUILDING_FAMILY["heavy"]), so
layout carries ALL of the separation — see iron_foundry.py and steelworks.py for
the worked pair that establishes how.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)

HUTS = ((-0.34, 0.24), (0.10, 0.32), (0.34, -0.06), (-0.10, -0.30))


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    steel_mat = flat_material("Steel", (0.475, 0.490, 0.515))
    berm_mat = flat_material("Berm", (0.310, 0.318, 0.259), alpha=0.86)
    way_mat = flat_material("Way", (0.451, 0.443, 0.412), alpha=0.92)
    sulfur_mat = flat_material("Sulfur", (0.780, 0.690, 0.196))

    # Each hut sits in its own earth traverse — separate patches, deliberately
    # not touching.
    for i, (hx, hy) in enumerate(HUTS):
        ground_patch(berm_mat, (hx, hy, 0.002), radius_x=0.21, radius_y=0.19,
                     sides=11, jitter=0.20, seed=1251 + i * 9, name="Traverse%d" % i)

    # Covered ways linking them — thin, so the gaps stay obvious.
    path(way_mat, [HUTS[0], (-0.12, 0.30), HUTS[1]], width=0.055, seed=1291)
    path(way_mat, [HUTS[1], (0.26, 0.14), HUTS[2]], width=0.055, seed=1297)
    path(way_mat, [HUTS[2], (0.14, -0.22), HUTS[3]], width=0.055, seed=1301)
    path(way_mat, [HUTS[3], (-0.26, -0.04), HUTS[0]], width=0.055, seed=1303)

    for i, (hx, hy) in enumerate(HUTS):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (hx, hy, 0.06),
             scale=(0.19, 0.17, 0.11), size=1.0)
        hip_roof(roof_mat, (hx, hy, 0.115), width=0.175, depth=0.155,
                 height=0.10, ridge_fraction=0.40, name="Hut%d" % i)

    # Sulfur and saltpetre stock in the middle, the one bright note.
    for i, (sx, sy) in enumerate(((0.0, 0.02), (0.08, -0.06))):
        part(bpy.ops.mesh.primitive_cone_add, sulfur_mat, (sx, sy, 0.05),
             radius1=0.075, radius2=0.0, depth=0.11)
