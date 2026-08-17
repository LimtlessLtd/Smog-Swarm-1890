"""assets/zombies/zombie_0_<facing>.png — variant 0 of ZombieVisuals.
VARIANT_COUNT (3). No role/accent color system (zombies aren't player
units) — the sickly green-grey base IS TacticalEntityLayer.ZOMBIE_COLOR's
own fallback tint, kept consistent rather than inventing a new palette.
Distinguishability across the 3 variants comes from build/pose instead:
this one is gaunt, upright, one arm raised — the "classic" silhouette.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

FLESH_COLOR = (0.33, 0.4, 0.27)   # Matches TacticalEntityLayer.ZOMBIE_COLOR exactly.
FLESH_DARK_COLOR = (0.22, 0.27, 0.18)
RAG_COLOR = (0.18, 0.16, 0.15)    # Tattered remnant clothing — dark, neutral, no accent color at all.


def build():
    flesh_mat = flat_material("Flesh", FLESH_COLOR)
    flesh_dark_mat = flat_material("FleshDark", FLESH_DARK_COLOR)
    rag_mat = flat_material("Rag", RAG_COLOR)

    # Gaunt legs — thinner than any player unit's leg cylinders.
    for side, forward in ((-0.12, 0.0), (0.12, -0.03)):
        part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
             (side, forward, 0.3), scale=(0.45, 0.45, 1.0), radius=0.12, depth=0.6)

    # Torso, hunched forward (tilted, not upright like every player unit's torso).
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
         (0, 0.05, 0.9), rotation=(0.25, 0, 0), radius=0.26, depth=0.55)

    # Torn rag clothing — a single ragged strip, not a full coat, so bare
    # flesh dominates the silhouette color unlike any clothed player unit.
    part(bpy.ops.mesh.primitive_cube_add, rag_mat,
         (0.05, 0.1, 0.85), scale=(0.28, 0.05, 0.35), size=1.0, rotation=(0.25, 0, 0.15))

    # Arms: one raised straight up (the "classic" shambler silhouette),
    # one hanging limp.
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_mat,
         (-0.22, 0.15, 1.3), rotation=(0.1, 0, 0.1), radius=0.06, depth=0.55)
    part(bpy.ops.mesh.primitive_cylinder_add, flesh_dark_mat,
         (0.24, 0.15, 0.85), rotation=(0.6, 0, -0.2), radius=0.06, depth=0.45)

    # Head, tilted/asymmetric — no clean vertical stack the way every
    # player unit's head-on-torso reads.
    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh_mat,
         (0.02, 0.12, 1.5), scale=(0.9, 0.85, 1.0), segments=9, ring_count=5, radius=0.18)
