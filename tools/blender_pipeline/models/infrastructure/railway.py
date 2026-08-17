"""assets/infrastructure/railway.png — Railway supply line, single-tier
(SupplyLineCatalog.get_max_tier() returns 0). Ballast bed, wooden sleepers
crossing the segment's width, and two parallel steel rails running its
full length — the "ladder" pattern that reads as a railway from directly
above at a glance, distinct from road.py's dot-grid setts and
bridge.py's solid plank deck.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BALLAST_COLOR = (0.42, 0.4, 0.38)
SLEEPER_COLOR = (0.32, 0.22, 0.14)
RAIL_COLOR = (0.34, 0.34, 0.36)


def build():
    ballast_mat = flat_material("Ballast", BALLAST_COLOR)
    sleeper_mat = flat_material("Sleeper", SLEEPER_COLOR)
    rail_mat = flat_material("Rail", RAIL_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, ballast_mat, (0, 0, 0.015), scale=(1.0, 0.4, 0.03), size=1.0)

    # Sleepers: perpendicular to the rails, evenly spaced along the full length.
    for i in range(9):
        x = -0.46 + i * 0.115
        part(bpy.ops.mesh.primitive_cube_add, sleeper_mat, (x, 0, 0.045), scale=(0.03, 0.36, 0.02), size=1.0)

    # Two rails running the segment's full length, set in from the sleeper ends.
    for y in (-0.14, 0.14):
        part(bpy.ops.mesh.primitive_cube_add, rail_mat, (0, y, 0.065), scale=(1.0, 0.025, 0.02), size=1.0)
