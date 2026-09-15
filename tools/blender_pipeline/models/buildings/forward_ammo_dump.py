"""assets/buildings/forward_ammo_dump.png — GameEnums.BuildingType.SUPPLY_DUMP.

Tier 1. A dump, not a building: rows of crates and shell stacks under open
revetments, with a slit trench and NO permanent structure bigger than a shelter.
Lots of small identical rectangles in ranked rows is the military family's
storage read, kept clear of gunpowder_mill's dispersed huts (which are buildings,
widely spaced) by being dense, low and uniform.

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
    crate_mat = flat_material("Crate", (0.478, 0.404, 0.251))
    shell_mat = flat_material("Shell", (0.412, 0.435, 0.380))
    berm_mat = flat_material("Berm", (0.337, 0.337, 0.271), alpha=0.92)

    ground_patch(ground_mat, (0.0, 0.0, 0.002), radius_x=0.54, radius_y=0.46,
                 sides=14, jitter=0.22, seed=1551, name="Dump")
    # Delivery road in, and a spur between the two stacks.
    path(track_mat, [(-0.60, -0.28), (-0.16, -0.20), (0.24, -0.24), (0.58, -0.18)],
         width=0.12, seed=1553)
    path(track_mat, [(-0.04, -0.22), (-0.02, 0.06)], width=0.08, seed=1559)

    # Earth revetments: two low banks the stacks shelter behind.
    for i, (bx, by) in enumerate(((-0.28, 0.30), (0.26, 0.30))):
        ground_patch(berm_mat, (bx, by, 0.003), radius_x=0.24, radius_y=0.10,
                     sides=11, jitter=0.18, seed=1561 + i * 5, name="Berm%d" % i)

    # Crate rows, ranked and uniform.
    for row in range(2):
        for col in range(4):
            part(bpy.ops.mesh.primitive_cube_add, crate_mat,
                 (-0.40 + col * 0.10, 0.20 - row * 0.095, 0.035),
                 scale=(0.075, 0.070, 0.040), size=1.0)
    # Shell stacks: cylinders on their sides, a different unit of storage.
    for row in range(2):
        for col in range(4):
            part(bpy.ops.mesh.primitive_cylinder_add, shell_mat,
                 (0.14 + col * 0.10, 0.20 - row * 0.095, 0.030),
                 rotation=(0.0, 1.5708, 0.0), radius=0.030, depth=0.080)

    # One shelter, the only roofed thing on the site.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (-0.34, -0.34, 0.05),
         scale=(0.20, 0.15, 0.09), size=1.0)
    hip_roof(roof_mat, (-0.34, -0.34, 0.095), width=0.18, depth=0.13,
             height=0.08, ridge_fraction=0.45)
