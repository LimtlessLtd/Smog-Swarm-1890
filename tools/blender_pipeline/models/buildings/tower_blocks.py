"""assets/buildings/tower_blocks.png — GameEnums.BuildingType.TOWER_BLOCKS,
Tier 2 Housing & Civil. A cluster of 3 tall thin towers of varying
height — the tallest housing silhouette on the roster, distinct from
terraced_tenement.py's low row and workhouse.py's single squat building.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WALL_COLORS = [(0.6, 0.52, 0.42), (0.52, 0.46, 0.4), (0.65, 0.56, 0.46)]
WINDOW_COLOR = (0.5, 0.56, 0.6)


def build():
    window_mat = flat_material("Window", WINDOW_COLOR)
    heights = [0.7, 0.9, 0.6]
    positions = [(-0.24, -0.05), (0.05, 0.05), (0.26, -0.1)]

    for i, ((x, y), h) in enumerate(zip(positions, heights)):
        wall_mat = flat_material("Wall%d" % i, WALL_COLORS[i])
        part(bpy.ops.mesh.primitive_cube_add, wall_mat, (x, y, h / 2.0), scale=(0.18, 0.18, h), size=1.0)
        # Window rows.
        for row in range(int(h / 0.15)):
            part(bpy.ops.mesh.primitive_cube_add, window_mat, (x, y + 0.09, 0.08 + row * 0.15),
                 scale=(0.1, 0.005, 0.04), size=1.0)
