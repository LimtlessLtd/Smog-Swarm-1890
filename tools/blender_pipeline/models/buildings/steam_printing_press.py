"""assets/buildings/steam_printing_press.png — GameEnums.BuildingType.
RESEARCH_INSTITUTE, Tier 1 Housing & Civil. A civic building with a
distinct rounded/domed roof (unlike every gabled house/shed on the
roster) and a stack of printed sheets out front — reads as "institution,"
not "workshop."
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WALL_COLOR = (0.62, 0.56, 0.46)
DOME_COLOR = (0.32, 0.34, 0.4)   # Blue-grey — a civic/institutional tone distinct from any industrial roof color.
PAPER_COLOR = (0.85, 0.82, 0.72)


def build():
    wall_mat = flat_material("Wall", WALL_COLOR)
    dome_mat = flat_material("Dome", DOME_COLOR)
    paper_mat = flat_material("Paper", PAPER_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, wall_mat, (0, 0, 0.2), radius=0.32, depth=0.4)

    # Domed roof — the only rounded (not peaked) roof on the Tier 0-1
    # roster, an immediate "this is different" silhouette cue.
    part(bpy.ops.mesh.primitive_uv_sphere_add, dome_mat, (0, 0, 0.42), scale=(1.0, 1.0, 0.7), segments=10, ring_count=6, radius=0.34)
    part(bpy.ops.mesh.primitive_cylinder_add, dome_mat, (0, 0, 0.64), radius=0.04, depth=0.14)  # Small finial spike.

    # Stack of printed sheets.
    for i in range(4):
        part(bpy.ops.mesh.primitive_cube_add, paper_mat, (0.3, 0.25, 0.02 + i * 0.025),
             scale=(0.14, 0.18, 0.01), size=1.0, rotation=(0, 0, i * 0.08))
