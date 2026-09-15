"""assets/buildings/tenant_farm.png — GameEnums.BuildingType.SMALLHOLDING_FARM.

Tier 0 smallholding, and the SMALLEST agriculture site: one cottage, one small
ploughed strip, a single pig sty. Scale is the differentiator across this family —
tenant_farm reads as one family's plot, estate_farm as a working farm with a silo,
industrial_farm and mechanised_farm as field systems. Nothing here is mechanised,
so there is no silo and no machinery: an empty-handed version of the same idea.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, furrows, ground_patch, path,
    family_materials,
)


def build():
    field_mat, barn_mat, cream_mat = family_materials("agriculture")
    crop_mat = flat_material("Crop", (0.475, 0.537, 0.239), alpha=0.78)
    soil_mat = flat_material("Soil", (0.361, 0.286, 0.192), alpha=0.95)
    yard_mat = flat_material("Yard", (0.451, 0.412, 0.333), alpha=0.86)
    track_mat = flat_material("Track", (0.639, 0.576, 0.463), alpha=0.92)

    ground_patch(crop_mat, (-0.22, 0.06, 0.002), radius_x=0.32, radius_y=0.34,
                 sides=13, jitter=0.22, seed=901, name="Strip")
    ground_patch(yard_mat, (0.20, -0.08, 0.003), radius_x=0.26, radius_y=0.28,
                 sides=11, jitter=0.24, seed=907, name="Yard")

    furrows(soil_mat, count=5, width=0.38, z=0.006, spacing=0.090, x=-0.22)
    path(track_mat, [(-0.02, -0.34), (0.10, -0.20), (0.18, -0.02)], width=0.08, seed=911)

    # Cottage: one hipped roof and one chimney. The whole building.
    part(bpy.ops.mesh.primitive_cube_add, cream_mat, (0.22, 0.10, 0.07),
         scale=(0.26, 0.24, 0.12), size=1.0)
    hip_roof(barn_mat, (0.22, 0.10, 0.13), width=0.24, depth=0.22,
             height=0.13, ridge_fraction=0.40)
    roof_vent(cream_mat, (0.22, 0.16, 0.24), radius=0.028, height=0.08)

    # Pig sty: a lean-to against the yard edge, no roof ridge — too small for one.
    part(bpy.ops.mesh.primitive_cube_add, barn_mat, (0.28, -0.26, 0.05),
         scale=(0.16, 0.13, 0.09), size=1.0)
