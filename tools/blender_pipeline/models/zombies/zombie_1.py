"""assets/zombies/zombie_1_<facing>.png — variant 1 of ZombieVisuals.
VARIANT_COUNT. A low, crawling posture — the whole body pitched forward
and down — is a completely different silhouette height/shape from
zombie_0.py's upright shambler, not just a recolor.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

FLESH_COLOR = (0.36, 0.42, 0.29)  # Slightly lighter/sicklier than zombie_0 — a visible variant, not identical.
FLESH_DARK_COLOR = (0.24, 0.29, 0.19)
RAG_COLOR = (0.16, 0.14, 0.13)


def build():
    flesh_mat = flat_material("Flesh", FLESH_COLOR)
    flesh_dark_mat = flat_material("FleshDark", FLESH_DARK_COLOR)
    rag_mat = flat_material("Rag", RAG_COLOR)

    # Legs, bent/crouched — much shorter effective height than zombie_0's
    # near-upright stance.
    for side, forward in ((-0.13, -0.05), (0.13, 0.08)):
        part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
             (side, forward, 0.2), rotation=(0.5, 0, 0), scale=(0.4, 0.4, 1.0), radius=0.11, depth=0.4)

    # Torso, pitched nearly horizontal — the defining silhouette difference
    # from every upright figure on the roster (player or zombie).
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
         (0, 0.15, 0.5), rotation=(1.1, 0, 0), radius=0.24, depth=0.6)

    part(bpy.ops.mesh.primitive_cube_add, rag_mat,
         (0, 0.15, 0.55), scale=(0.26, 0.3, 0.05), size=1.0, rotation=(1.1, 0, 0))

    # Arms: both forward, low, dragging — a crawling gesture, not the
    # raised/limp pair zombie_0 uses.
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_dark_mat,
         (-0.18, 0.5, 0.3), rotation=(1.4, 0, 0.15), radius=0.06, depth=0.5)
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
         (0.18, 0.48, 0.28), rotation=(1.4, 0, -0.15), radius=0.06, depth=0.5)

    # Head, low and forward — level with the torso instead of stacked above it.
    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh_mat,
         (0, 0.42, 0.42), scale=(0.9, 0.9, 0.85), segments=9, ring_count=5, radius=0.17)
