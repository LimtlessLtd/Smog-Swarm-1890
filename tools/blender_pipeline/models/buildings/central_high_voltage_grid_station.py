"""assets/buildings/central_high_voltage_grid_station.png — GameEnums.
BuildingType.CENTRAL_HIGH_VOLTAGE_GRID_STATION, Tier 5 Industry &
Extraction. A pylon lattice tower with cross-arms and insulators — the
only building with an open lattice-frame silhouette (see-through, not a
solid mass), reading as electrical infrastructure rather than a factory.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

STEEL_COLOR = (0.42, 0.42, 0.44)
INSULATOR_COLOR = (0.75, 0.72, 0.65)
SPARK_COLOR = (0.6, 0.85, 0.95)


def build():
    steel_mat = flat_material("Steel", STEEL_COLOR)
    insulator_mat = flat_material("Insulator", INSULATOR_COLOR)
    spark_mat = flat_material("Spark", SPARK_COLOR)

    for x in (-0.16, 0.16):
        for y in (-0.16, 0.16):
            part(bpy.ops.mesh.primitive_cylinder_add, steel_mat, (x * 0.4, y * 0.4, 0.5),
                 radius=0.045, depth=1.0)

    for z in (0.25, 0.55, 0.85):
        width = 0.5 - z * 0.35
        part(bpy.ops.mesh.primitive_cube_add, steel_mat, (0, 0, z), scale=(width, 0.04, 0.04), size=1.0)

    for x in (-0.2, 0.2):
        part(bpy.ops.mesh.primitive_cylinder_add, insulator_mat, (x, 0, 0.9), radius=0.03, depth=0.14)
        part(bpy.ops.mesh.primitive_uv_sphere_add, spark_mat, (x, 0, 0.98), segments=6, ring_count=4, radius=0.03)
