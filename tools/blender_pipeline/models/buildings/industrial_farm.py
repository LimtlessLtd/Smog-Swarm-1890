"""assets/buildings/industrial_farm.png — GameEnums.BuildingType.INDUSTRIAL_FARM.

Tier 2. Where estate_farm is one field and a yard, this is a FIELD SYSTEM: three
separate ploughed blocks divided by headlands, worked from a central yard with a
threshing barn. Reading down the family, the field count is the tier.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, furrows, ground_patch, path,
    family_materials,
)


def build():
    field_mat, barn_mat, cream_mat = family_materials("agriculture")
    crop_mat = flat_material("Crop", (0.490, 0.553, 0.247), alpha=0.80)
    soil_mat = flat_material("Soil", (0.361, 0.286, 0.192), alpha=0.95)
    yard_mat = flat_material("Yard", (0.451, 0.412, 0.333), alpha=0.86)
    track_mat = flat_material("Track", (0.639, 0.576, 0.463), alpha=0.92)

    # Three fields, each its own patch with its own furrow direction implied by
    # spacing — the headlands between them are transparent, so terrain shows.
    blocks = ((-0.40, 0.26, 0.26, 0.22, 921), (-0.40, -0.22, 0.26, 0.22, 929),
              (0.04, 0.02, 0.28, 0.40, 937))
    for bx, by, rx, ry, seed in blocks:
        ground_patch(crop_mat, (bx, by, 0.002), radius_x=rx, radius_y=ry,
                     sides=12, jitter=0.18, seed=seed, name="Field%d" % seed)
    furrows(soil_mat, count=4, width=0.40, z=0.006, spacing=0.085, x=-0.40)
    furrows(soil_mat, count=6, width=0.42, z=0.006, spacing=0.105, x=0.04)

    ground_patch(yard_mat, (0.42, -0.06, 0.003), radius_x=0.26, radius_y=0.34,
                 sides=11, jitter=0.24, seed=941, name="Yard")
    # Headland track running the length of the system, linking all three fields.
    path(track_mat, [(-0.62, 0.02), (-0.20, 0.00), (0.16, -0.04), (0.42, -0.06)],
         width=0.09, seed=947)

    # Threshing barn plus a pair of ricks — the processing this tier adds.
    part(bpy.ops.mesh.primitive_cube_add, cream_mat, (0.44, 0.12, 0.08),
         scale=(0.30, 0.28, 0.14), size=1.0)
    hip_roof(barn_mat, (0.44, 0.12, 0.15), width=0.28, depth=0.26,
             height=0.14, ridge_fraction=0.48)
    # Corn ricks: three small straw cones, NOT two pale cylinders. Drawn at
    # cream_mat and paired they read as mechanised_farm's twin silos, which is
    # that building's own tier marker — measured on a render, they were
    # indistinguishable.
    rick_mat = flat_material("Rick", (0.639, 0.545, 0.286))
    for i, y in enumerate((-0.16, -0.28, -0.40)):
        part(bpy.ops.mesh.primitive_cone_add, rick_mat, (0.44 - (i % 2) * 0.05, y, 0.05),
             radius1=0.065, radius2=0.0, depth=0.13)
