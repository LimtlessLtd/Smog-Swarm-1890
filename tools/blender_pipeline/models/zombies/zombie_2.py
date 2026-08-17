"""assets/zombies/zombie_2_<facing>.png — variant 2 of ZombieVisuals.
VARIANT_COUNT. A bloated, heavy-set build — wider than tall, arms out to
the sides — distinct from zombie_0.py's gaunt upright shambler and
zombie_1.py's low crawler; all three read as different creatures from
silhouette alone, not the same base recolored.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

FLESH_COLOR = (0.3, 0.36, 0.24)  # Darker/more mottled than the other two variants.
FLESH_DARK_COLOR = (0.2, 0.24, 0.16)
RAG_COLOR = (0.2, 0.17, 0.14)


def build():
    flesh_mat = flat_material("Flesh", FLESH_COLOR)
    flesh_dark_mat = flat_material("FleshDark", FLESH_DARK_COLOR)
    rag_mat = flat_material("Rag", RAG_COLOR)

    for side, forward in ((-0.16, 0.0), (0.16, 0.0)):
        part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
             (side, forward, 0.28), scale=(0.6, 0.6, 1.0), radius=0.15, depth=0.55)

    # Bloated torso — much wider than every other figure on the roster
    # (radius 0.4 vs ~0.2-0.3 everywhere else), the defining trait of this variant.
    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh_mat,
         (0, 0, 0.95), scale=(1.3, 1.1, 1.0), segments=10, ring_count=6, radius=0.32)

    part(bpy.ops.mesh.primitive_cube_add, rag_mat,
         (0, 0.28, 0.9), scale=(0.3, 0.04, 0.3), size=1.0)

    # Arms held straight out to the sides — a T-pose-adjacent stance no
    # other unit or zombie variant uses, maximizing this variant's already
    # wide silhouette even further.
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_dark_mat,
         (-0.42, 0.0, 1.0), rotation=(0, 1.4, 0), radius=0.07, depth=0.4)
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
         (0.42, 0.0, 1.0), rotation=(0, 1.4, 0), radius=0.07, depth=0.4)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh_mat,
         (0, 0, 1.42), scale=(1.0, 1.0, 0.9), segments=9, ring_count=5, radius=0.19)
