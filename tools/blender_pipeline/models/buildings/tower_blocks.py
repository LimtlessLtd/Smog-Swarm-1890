"""assets/buildings/tower_blocks.png — GameEnums.BuildingType.TOWER_BLOCKS.

Tier 2 housing. Height is invisible from directly overhead, so the tier cannot be
drawn as "taller" — it is drawn as FOOTPRINT instead: three small square towers
standing apart on open ground, where terraced_tenement is four bays welded into a
row and workhouse is a closed ring. Small-and-separate against long-and-joined.
Each tower gets a flat roof with a stair head and a water tank, which is what a
tall building actually shows from the air.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, ground_patch, path, family_materials,
)

TOWERS = ((-0.30, 0.16), (0.10, 0.28), (0.24, -0.16))


def build():
    cobble_mat, roof_mat, chimney_mat = family_materials("housing")
    dirt_mat = flat_material("Dirt", (0.376, 0.365, 0.345), alpha=0.76)
    deck_mat = flat_material("Deck", (0.365, 0.353, 0.345))
    path_mat = flat_material("Walk", (0.506, 0.494, 0.478), alpha=0.92)

    ground_patch(dirt_mat, (-0.02, 0.04, 0.002), radius_x=0.56, radius_y=0.50,
                 sides=15, jitter=0.22, seed=981, name="Estate")

    # Walkways between the towers — the "paths between the buildings" are load
    # bearing here, because without them three squares read as three assets.
    path(path_mat, [TOWERS[0], (-0.10, 0.22), TOWERS[1]], width=0.08, seed=983)
    path(path_mat, [TOWERS[1], (0.20, 0.06), TOWERS[2]], width=0.08, seed=987)
    path(path_mat, [TOWERS[2], (0.06, -0.34), (-0.30, -0.40)], width=0.08, seed=991)

    for i, (x, y) in enumerate(TOWERS):
        part(bpy.ops.mesh.primitive_cube_add, cobble_mat, (x, y, 0.20),
             scale=(0.26, 0.26, 0.40), size=1.0)
        # Flat roof deck inset from the parapet, so the edge reads as a wall.
        part(bpy.ops.mesh.primitive_cube_add, deck_mat, (x, y, 0.405),
             scale=(0.21, 0.21, 0.02), size=1.0)
        # Stair head and water tank: the two lumps every flat roof has.
        part(bpy.ops.mesh.primitive_cube_add, roof_mat, (x - 0.05, y + 0.05, 0.435),
             scale=(0.08, 0.08, 0.05), size=1.0)
        part(bpy.ops.mesh.primitive_cylinder_add, roof_mat, (x + 0.06, y - 0.05, 0.435),
             radius=0.045, depth=0.05)
