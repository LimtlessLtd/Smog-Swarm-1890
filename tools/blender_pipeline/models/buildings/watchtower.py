"""assets/buildings/watchtower.png — GameEnums.BuildingType.WATCHTOWER,
Tier 0 Housing & Civil. A tall wooden lookout tower — the tallest, thinnest
silhouette in the Tier 0 building set, unmistakable from any of the
squat sheds/houses around it.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WOOD_COLOR = (0.47, 0.277, 0.099)   # Lightened from the first pass — too close to ROOF_COLOR's value to read as a separate part.
PLATFORM_COLOR = (0.336, 0.191, 0.062)
ROOF_COLOR = (0.616, 0.095, 0.0)  # Warm red-brown, clearly distinct from the wood tone now.


def build():
    wood_mat = flat_material("Wood", WOOD_COLOR)
    platform_mat = flat_material("Platform", PLATFORM_COLOR)
    roof_mat = flat_material("Roof", ROOF_COLOR)

    # Four angled corner legs, converging toward the top — a real lookout
    # tower's braced-leg silhouette, not a straight vertical box. Radius
    # bumped from the first pass's 0.025 to 0.045 — thinner than that got
    # swallowed almost entirely by the Freestyle outline (same failure
    # class as armoured_command_car.py's first-pass antenna), confirmed on
    # a real render, not assumed.
    for x in (-0.16, 0.16):
        for y in (-0.16, 0.16):
            part(bpy.ops.mesh.primitive_cylinder_add, wood_mat, (x * 0.6, y * 0.6, 0.4),
                 rotation=(0, 0, 0), scale=(1.0, 1.0, 1.0), radius=0.045, depth=0.8)

    # Cross-bracing — thickened the same way.
    for z in (0.2, 0.5):
        part(bpy.ops.mesh.primitive_cube_add, wood_mat, (0, 0, z), scale=(0.24, 0.035, 0.035), size=1.0)
        part(bpy.ops.mesh.primitive_cube_add, wood_mat, (0, 0, z), scale=(0.035, 0.24, 0.035), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, platform_mat, (0, 0, 0.82), scale=(0.24, 0.24, 0.04), size=1.0)

    # Railed lookout box on top, with a small peaked roof.
    part(bpy.ops.mesh.primitive_cube_add, wood_mat, (0, 0, 0.94), scale=(0.2, 0.2, 0.16), size=1.0)
    part(bpy.ops.mesh.primitive_cone_add, roof_mat, (0, 0, 1.08), radius1=0.18, radius2=0.02, depth=0.16)
