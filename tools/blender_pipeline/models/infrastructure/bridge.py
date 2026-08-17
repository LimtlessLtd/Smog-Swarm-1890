"""assets/infrastructure/bridge.png — Bridge supply line (design_doc.md
§3's Wooden/Brick Arch/Iron Girder/Steel Truss tiers; one BuildMenuView
icon per SupplyLineType, not per tier — same precedent as road.py — so
this renders the Wooden tier, the doc's own Tier-0 baseline). A solid
wooden plank deck with side rails/posts and a strip of water visible at
each end, spanning the same segment width canal.py's channel uses — the
detail that reads as "crossing water" rather than railway.py's ballasted
bed.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WATER_COLOR = (0.22, 0.4, 0.52)
PLANK_COLOR = (0.5, 0.36, 0.22)
PLANK_DARK_COLOR = (0.4, 0.28, 0.16)
POST_COLOR = (0.34, 0.24, 0.14)


def build():
    water_mat = flat_material("Water", WATER_COLOR)
    plank_mat = flat_material("Plank", PLANK_COLOR)
    plank_dark_mat = flat_material("PlankDark", PLANK_DARK_COLOR)
    post_mat = flat_material("Post", POST_COLOR)

    # Water visible only at the very ends of the segment — the deck covers
    # the middle, unlike canal.py's open channel running the full length.
    for x in (-0.46, 0.46):
        part(bpy.ops.mesh.primitive_cube_add, water_mat, (x, 0, -0.005), scale=(0.1, 0.5, 0.01), size=1.0)

    # Plank deck, laid crosswise (perpendicular to the span) like a real
    # timber bridge deck — same "ladder" silhouette railway.py's sleepers
    # use, but as a solid abutting run of planks, no gaps between them.
    for i in range(12):
        x = -0.46 + i * 0.084
        mat = plank_dark_mat if i % 2 else plank_mat
        part(bpy.ops.mesh.primitive_cube_add, mat, (x, 0, 0.03), scale=(0.038, 0.42, 0.06), size=1.0)

    # Side rails and corner posts.
    for y in (-0.42, 0.42):
        part(bpy.ops.mesh.primitive_cube_add, post_mat, (0, y, 0.08), scale=(1.0, 0.02, 0.02), size=1.0)
        for x in (-0.42, 0.0, 0.42):
            part(bpy.ops.mesh.primitive_cylinder_add, post_mat, (x, y, 0.09), radius=0.02, depth=0.18)
