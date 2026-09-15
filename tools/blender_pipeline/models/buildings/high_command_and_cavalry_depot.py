"""assets/buildings/high_command_and_cavalry_depot.png — GameEnums.BuildingType.HIGH_COMMAND_AND_CAVALRY_DEPOT.

Tier 3, the top of the military family. Keeps the parade ground but adds STABLE
LINES: two long narrow ranges divided into loose boxes, drawn as a repeating comb
of partitions. A comb of many small bays is unlike any barrack range (few large
bays) and unlike the roundhouse fan (radial), so the cavalry half reads at a
glance. A pyramid-capped command block with a gold finial borrows the civic
family's prestige marker, which is the point of a headquarters.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and per-family signature shapes, and
its organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, yard_plate, ground_patch, path,
    family_materials,
)


def build():
    olive_mat, roof_mat, flag_mat = family_materials("military")
    parade_mat = flat_material("Parade", (0.545, 0.522, 0.416))
    ground_mat = flat_material("Trodden", (0.388, 0.380, 0.294), alpha=0.80)
    track_mat = flat_material("Track", (0.573, 0.553, 0.447), alpha=0.92)
    gold_mat = flat_material("Gold", (0.855, 0.671, 0.239))
    straw_mat = flat_material("Straw", (0.612, 0.545, 0.337), alpha=0.92)

    ground_patch(ground_mat, (-0.10, 0.06, 0.002), radius_x=0.58, radius_y=0.50,
                 sides=15, jitter=0.18, seed=1491, name="Compound")
    ground_patch(straw_mat, (0.30, -0.06, 0.003), radius_x=0.28, radius_y=0.42,
                 sides=12, jitter=0.20, seed=1499, name="StableGround")

    yard_plate(parade_mat, location=(-0.28, 0.08, 0.004), width=0.42, depth=0.40,
               thickness=0.012)
    path(track_mat, [(-0.28, -0.18), (0.02, -0.26), (0.28, -0.34)], width=0.10, seed=1511)

    # Command block: pyramid cap and finial, the prestige marker.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (-0.30, 0.38, 0.11),
         scale=(0.34, 0.24, 0.20), size=1.0)
    hip_roof(roof_mat, (-0.30, 0.38, 0.205), width=0.32, depth=0.22,
             height=0.20, ridge_fraction=0.0, name="CommandCap")
    part(bpy.ops.mesh.primitive_uv_sphere_add, gold_mat, (-0.30, 0.38, 0.42),
         segments=10, ring_count=6, radius=0.040)

    # Barrack range along the parade ground.
    part(bpy.ops.mesh.primitive_cube_add, olive_mat, (-0.30, -0.22, 0.08),
         scale=(0.46, 0.17, 0.14), size=1.0)
    hip_roof(roof_mat, (-0.30, -0.22, 0.15), width=0.44, depth=0.15,
             height=0.12, ridge_fraction=0.74, name="Barrack")

    # Stable lines: two ranges combed into loose boxes.
    for line, x in enumerate((0.20, 0.44)):
        part(bpy.ops.mesh.primitive_cube_add, olive_mat, (x, -0.04, 0.07),
             scale=(0.17, 0.72, 0.13), size=1.0)
        hip_roof(roof_mat, (x, -0.04, 0.135), width=0.155, depth=0.70,
                 height=0.11, ridge_fraction=0.22, name="Stable%d" % line)
        for j in range(6):
            part(bpy.ops.mesh.primitive_cube_add, parade_mat,
                 (x, -0.34 + j * 0.12, 0.215), scale=(0.16, 0.016, 0.02), size=1.0)
