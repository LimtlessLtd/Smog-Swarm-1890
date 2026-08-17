"""assets/infrastructure/canal.png — Canal supply line, single-tier
(SupplyLineCatalog.get_max_tier() returns 0). An open water channel
flanked by two raised tow-path banks — no deck/structure over the water,
the detail that distinguishes it from bridge.py (which spans a gap the
same width) at a glance.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

WATER_COLOR = (0.22, 0.4, 0.52)
WATER_DARK_COLOR = (0.16, 0.32, 0.44)
BANK_COLOR = (0.42, 0.38, 0.26)


def build():
    water_mat = flat_material("Water", WATER_COLOR)
    water_dark_mat = flat_material("WaterDark", WATER_DARK_COLOR)
    bank_mat = flat_material("Bank", BANK_COLOR)

    # Tow-path banks, raised slightly above the water surface.
    for y in (-0.32, 0.32):
        part(bpy.ops.mesh.primitive_cube_add, bank_mat, (0, y, 0.025), scale=(1.0, 0.14, 0.05), size=1.0)

    part(bpy.ops.mesh.primitive_cube_add, water_mat, (0, 0, -0.005), scale=(1.0, 0.5, 0.01), size=1.0)

    # Ripple lines — thin darker strips breaking up the flat water fill so it
    # reads as water rather than a solid blue rectangle from directly above.
    for i, y in enumerate((-0.1, 0.03, 0.14)):
        x_offset = 0.06 if i % 2 else -0.06
        part(bpy.ops.mesh.primitive_cube_add, water_dark_mat, (x_offset, y, 0.001), scale=(0.7, 0.015, 0.001), size=1.0)
