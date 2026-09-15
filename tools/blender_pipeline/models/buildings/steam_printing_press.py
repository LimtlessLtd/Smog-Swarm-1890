"""assets/buildings/steam_printing_press.png — GameEnums.BuildingType.RESEARCH_INSTITUTE.

Civic family (BuildingVisuals._texture_key keeps the "steam_printing_press" art
key). Distinguished from town_hall by having a DOME rather than a pyramid-capped
tower: a dome from directly above is a set of concentric rings, which is a shape
no other building on the roster draws, and it reads as "institute" the way the
finial reads as "hall". Paved forecourt, formal beds, no industry.

Re-authored 2026-09-15 for the straight-down camera. See render_common's
BUILDING_FAMILY block for the shared palette and signature shapes, and its
organic-ground block for why the old full-quad plate went.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, yard_plate, ring, ground_patch, path,
    family_materials,
)


def build():
    stone_mat, roof_mat, gold_mat = family_materials("civic")
    lawn_mat = flat_material("Lawn", (0.404, 0.451, 0.286), alpha=0.72)
    gravel_mat = flat_material("Gravel", (0.596, 0.565, 0.494), alpha=0.88)
    glass_mat = flat_material("Glass", (0.612, 0.686, 0.702))

    ground_patch(lawn_mat, (0.0, 0.0, 0.002), radius_x=0.58, radius_y=0.50,
                 sides=15, jitter=0.20, seed=993, name="Grounds")
    path(gravel_mat, [(-0.02, -0.56), (0.01, -0.45), (0.0, -0.34)], width=0.10, seed=997)
    path(gravel_mat, [(-0.50, 0.06), (-0.30, 0.28), (0.10, 0.34), (0.46, 0.22)],
         width=0.08, seed=1009)

    yard_plate(stone_mat, location=(0.0, -0.26, 0.004), width=0.60, depth=0.22,
               thickness=0.012)

    # Main block: a broad hipped range.
    part(bpy.ops.mesh.primitive_cube_add, stone_mat, (0.0, 0.04, 0.10),
         scale=(0.76, 0.52, 0.18), size=1.0)
    hip_roof(roof_mat, (0.0, 0.04, 0.19), width=0.72, depth=0.48,
             height=0.16, ridge_fraction=0.60)

    # Dome over the centre: concentric rings from above, the civic family's
    # second signature after the finial.
    part(bpy.ops.mesh.primitive_cylinder_add, stone_mat, (0.0, 0.04, 0.30),
         radius=0.22, depth=0.10)
    part(bpy.ops.mesh.primitive_uv_sphere_add, roof_mat, (0.0, 0.04, 0.34),
         scale=(1.0, 1.0, 0.62), segments=20, ring_count=10, radius=0.20)
    ring(stone_mat, (0.0, 0.04, 0.44), outer=0.11, thickness=0.024, height=0.05)
    part(bpy.ops.mesh.primitive_cylinder_add, glass_mat, (0.0, 0.04, 0.47),
         radius=0.055, depth=0.03)
    part(bpy.ops.mesh.primitive_uv_sphere_add, gold_mat, (0.0, 0.04, 0.50),
         segments=10, ring_count=6, radius=0.034)
