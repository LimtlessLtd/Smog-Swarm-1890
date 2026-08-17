"""assets/buildings/iron_foundry.png — GameEnums.BuildingType.IRON_FOUNDRY,
Tier 2 Industry & Extraction. Bigger and more elaborate than
steam_furnace.py — a tall brick stack over an open forge shed, riffing on
the same brief the existing Gemini-generated cast_iron_foundry.png
answered (forge, chimney, fenced yard) but built from primitives instead.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, gable_roof, chimney, fence_perimeter  # noqa: E402

BRICK_COLOR = (0.504, 0.168, 0.055)
ROOF_COLOR = (0.336, 0.267, 0.198)
GLOW_COLOR = (1.0, 0.375, 0.0)
FENCE_COLOR = (0.358, 0.229, 0.083)


def build():
    brick_mat = flat_material("Brick", BRICK_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)
    glow_mat = flat_material("Glow", GLOW_COLOR)
    fence_mat = flat_material("Fence", FENCE_COLOR)

    fence_perimeter(fence_mat, count=12, distance=0.6, post_height=0.14, post_radius=0.02)

    part(bpy.ops.mesh.primitive_cube_add, brick_mat, (-0.05, -0.05, 0.2), scale=(0.4, 0.36, 0.2), size=1.0)
    gable_roof(roof_mat, (-0.05, -0.05, 0.42), width=0.44, depth=0.4, height=0.2, ridge_along_y=False)

    chimney(brick_mat, (0.28, 0.15, 0.7), height=0.6, radius=0.09)
    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (0.28, 0.15, 0.98),
         scale=(0.7, 0.7, 0.2), radius=0.06, depth=0.05)  # Glowing stack mouth.

    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (0.05, 0.28, 0.1),
         rotation=(1.5708, 0, 0), scale=(1.0, 1.0, 0.4), radius=0.1, depth=0.05)  # Forge mouth glow at ground level.
