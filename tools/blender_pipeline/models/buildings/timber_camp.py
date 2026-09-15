"""assets/buildings/timber_camp.png — GameEnums.BuildingType.LUMBER_YARD.

Tier 0 forestry, on the extraction family's palette. Its signature is LOG ENDS —
stacks of felled trunks seen from above as tight rows of circles, which nothing
else on the roster draws. Standing timber at the edges (dark canopy discs) marks
where the cutting is happening, and a skid road runs from the stand to the stacks.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    dirt_mat = flat_material("Dirt", (0.427, 0.373, 0.278), alpha=0.82)
    track_mat = flat_material("Track", (0.529, 0.463, 0.349), alpha=0.92)
    log_mat = flat_material("Log", (0.545, 0.408, 0.243))
    bark_mat = flat_material("Bark", (0.318, 0.235, 0.145))
    canopy_mat = flat_material("Canopy", (0.204, 0.302, 0.169))

    ground_patch(dirt_mat, (0.02, -0.06, 0.002), radius_x=0.52, radius_y=0.44,
                 sides=14, jitter=0.24, seed=1013, name="Clearing")

    # Standing timber along two edges — the resource, not yet cut.
    for i, (cx, cy, r) in enumerate(((-0.52, 0.34, 0.15), (-0.22, 0.44, 0.13),
                                     (0.16, 0.46, 0.14), (0.50, 0.32, 0.12))):
        part(bpy.ops.mesh.primitive_uv_sphere_add, canopy_mat, (cx, cy, 0.20),
             scale=(1.0, 1.0, 0.55), segments=11, ring_count=6, radius=r)

    path(track_mat, [(-0.30, 0.22), (-0.10, 0.02), (0.14, -0.16)], width=0.12, seed=1019)

    # Log stacks: rows of trunk ends. Two stacks at different orientations so
    # the site does not read as a single striped rectangle.
    for row in range(3):
        for col in range(4):
            part(bpy.ops.mesh.primitive_cylinder_add, log_mat,
                 (-0.34 + col * 0.088, -0.22 - row * 0.085, 0.055),
                 radius=0.040, depth=0.11)
            part(bpy.ops.mesh.primitive_cylinder_add, bark_mat,
                 (-0.34 + col * 0.088, -0.22 - row * 0.085, 0.112),
                 radius=0.040, depth=0.006)
    for row in range(2):
        for col in range(3):
            part(bpy.ops.mesh.primitive_cylinder_add, log_mat,
                 (0.22 + col * 0.088, -0.12 - row * 0.085, 0.055),
                 radius=0.040, depth=0.11)

    # Sawyer's hut — small, timber, the only structure on a Tier 0 site.
    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (0.36, 0.14, 0.06),
         scale=(0.20, 0.18, 0.11), size=1.0)
    hip_roof(timber_mat, (0.36, 0.14, 0.11), width=0.18, depth=0.16,
             height=0.10, ridge_fraction=0.40)
