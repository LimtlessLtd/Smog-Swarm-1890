"""assets/buildings/synthetic_chemical_refinery.png — GameEnums.
BuildingType.SYNTHETIC_CHEMICAL_REFINERY, Tier 5 Industry & Extraction.
Three tall thin distillation columns connected by pipework — the
multi-column-plus-pipe silhouette is a real refinery shape, distinct from
every single-vessel/single-chimney industrial building elsewhere on the roster.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

COLUMN_COLOR = (0.5, 0.5, 0.54)
PIPE_COLOR = (0.283, 0.616, 0.366)  # Green pipework — a color no other building uses, "chemical" flavor.
BASE_COLOR = (0.3, 0.29, 0.3)


def build():
    column_mat = flat_material("Column", COLUMN_COLOR)
    pipe_mat = flat_material("Pipe", PIPE_COLOR)
    base_mat = flat_material("Base", BASE_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, base_mat, (0, 0, 0.04), scale=(0.6, 0.4, 0.08), size=1.0)

    heights = [0.55, 0.75, 0.45]
    for i, (x, h) in enumerate(zip((-0.2, 0.05, 0.28), heights)):
        part(bpy.ops.mesh.primitive_cylinder_add, column_mat, (x, -0.1, 0.08 + h / 2.0), radius=0.06, depth=h)
        part(bpy.ops.mesh.primitive_cylinder_add, pipe_mat, (x, -0.1, 0.08 + h), scale=(1.3, 1.3, 0.2), radius=0.06, depth=0.03)

    # Connecting pipe run between the columns.
    part(bpy.ops.mesh.primitive_cube_add, pipe_mat, (0.04, -0.1, 0.35), scale=(0.5, 0.025, 0.025), size=1.0)
