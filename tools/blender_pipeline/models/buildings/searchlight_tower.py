"""assets/buildings/searchlight_tower.png — GameEnums.BuildingType.SEARCH_LIGHT.

Tier 2 Defense Works, the only entry left in that category. Deliberately
watchtower's silhouette plus the thing that makes it a searchlight: a big pale
LENS disc on the platform and a generator hut at the foot, wired to it. A player
who knows the watchtower should read this as "watchtower with a light", because
mechanically that is what it is.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)


def build():
    olive_mat, roof_mat, flag_mat = family_materials("military")
    ground_mat = flat_material("Trodden", (0.388, 0.380, 0.294), alpha=0.80)
    track_mat = flat_material("Track", (0.573, 0.553, 0.447), alpha=0.92)
    steel_mat = flat_material("Steel", (0.435, 0.451, 0.478))
    lens_mat = flat_material("Lens", (0.925, 0.906, 0.784))

    ground_patch(ground_mat, (-0.04, 0.04, 0.002), radius_x=0.38, radius_y=0.34,
                 sides=12, jitter=0.24, seed=1531, name="Ground")
    ground_patch(ground_mat, (0.34, -0.28, 0.002), radius_x=0.18, radius_y=0.15,
                 sides=10, jitter=0.28, seed=1537, name="HutGround")
    # Cable run from the generator hut to the tower foot.
    path(track_mat, [(0.30, -0.24), (0.14, -0.10), (0.02, 0.00)], width=0.055, seed=1541)

    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part(bpy.ops.mesh.primitive_cube_add, steel_mat,
             (-0.04 + dx * 0.14, 0.04 + dy * 0.14, 0.15),
             scale=(0.042, 0.042, 0.30), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, steel_mat, (-0.04, 0.04, 0.31),
         scale=(0.40, 0.40, 0.03), size=1.0)

    # The lens: a big pale disc in a steel drum, the brightest thing here.
    part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (-0.04, 0.04, 0.37),
         radius=0.175, depth=0.10)
    part(bpy.ops.mesh.primitive_cylinder_add, lens_mat, (-0.04, 0.04, 0.425),
         radius=0.135, depth=0.03)

    # Generator hut at the foot.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (0.34, -0.28, 0.06),
         scale=(0.20, 0.17, 0.11), size=1.0)
    hip_roof(roof_mat, (0.34, -0.28, 0.115), width=0.18, depth=0.15,
             height=0.10, ridge_fraction=0.42)
