"""assets/buildings/mechanised_farm.png — GameEnums.BuildingType.MECHANISED_FARM.

Tier 3, the top of the family. One very large worked block instead of several
small ones, with a machinery shed and a pair of silos — the only agriculture site
with TWO silos, which is what separates it from estate_farm's one at a glance.
The field is ruled in long unbroken furrows because a machine ploughs further than
a horse.

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
    crop_mat = flat_material("Crop", (0.502, 0.565, 0.255), alpha=0.82)
    soil_mat = flat_material("Soil", (0.361, 0.286, 0.192), alpha=0.95)
    yard_mat = flat_material("Yard", (0.451, 0.412, 0.333), alpha=0.86)
    track_mat = flat_material("Track", (0.639, 0.576, 0.463), alpha=0.92)

    ground_patch(crop_mat, (-0.20, 0.02, 0.002), radius_x=0.52, radius_y=0.48,
                 sides=16, jitter=0.14, seed=951, name="Field")
    furrows(soil_mat, count=9, width=0.80, z=0.006, spacing=0.090, x=-0.20)

    ground_patch(yard_mat, (0.42, -0.02, 0.003), radius_x=0.26, radius_y=0.40,
                 sides=11, jitter=0.22, seed=957, name="Yard")
    path(track_mat, [(-0.66, -0.34), (-0.10, -0.30), (0.34, -0.14), (0.42, 0.04)],
         width=0.11, seed=961)

    # Machinery shed: wide doors facing the field, so the front edge is open.
    part(bpy.ops.mesh.primitive_cube_add, cream_mat, (0.44, 0.22, 0.09),
         scale=(0.32, 0.30, 0.16), size=1.0)
    hip_roof(barn_mat, (0.44, 0.22, 0.17), width=0.30, depth=0.28,
             height=0.15, ridge_fraction=0.50)

    # TWO silos — the family's tier marker.
    for y in (-0.16, -0.36):
        part(bpy.ops.mesh.primitive_cylinder_add, cream_mat, (0.42, y, 0.20),
             radius=0.115, depth=0.40)
        part(bpy.ops.mesh.primitive_uv_sphere_add, cream_mat, (0.42, y, 0.40),
             scale=(1.0, 1.0, 0.55), segments=14, ring_count=7, radius=0.115)
