"""assets/buildings/advanced_coal_powerplant.png — GameEnums.BuildingType.
ADVANCED_COAL_POWERPLANT, Tier 3 Industry & Extraction. Three chimneys
(up from coal_powerplant.py's two) plus a pair of cooling-tower domes —
the domed towers are a new silhouette element establishing a bigger,
later-tier power plant.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, chimney  # noqa: E402

HALL_COLOR = (0.36, 0.34, 0.34)
DARK_COLOR = (0.2, 0.19, 0.19)
TOWER_COLOR = (0.616, 0.573, 0.51)


def build():
    hall_mat = flat_material("Hall", HALL_COLOR)
    dark_mat = flat_material("Dark", DARK_COLOR)
    tower_mat = flat_material("Tower", TOWER_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, hall_mat, (0, -0.15, 0.16), scale=(0.6, 0.28, 0.16), size=1.0)

    for x in (-0.24, 0, 0.24):
        chimney(dark_mat, (x, -0.15, 0.62), height=0.5, radius=0.055)

    # Cooling towers: wide hyperboloid-ish domes (approximated with a
    # cylinder + dome cap), a silhouette no earlier power building has.
    for x in (-0.35, 0.35):
        part(bpy.ops.mesh.primitive_cylinder_add, tower_mat, (x, 0.2, 0.22), scale=(1.0, 1.0, 1.0), radius=0.16, depth=0.36)
        part(bpy.ops.mesh.primitive_uv_sphere_add, tower_mat, (x, 0.2, 0.4), scale=(1.0, 1.0, 0.4), segments=9, ring_count=5, radius=0.16)
