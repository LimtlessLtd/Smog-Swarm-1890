"""assets/props/rock.png — scattered decorative prop. An angular grey
boulder cluster — distinct from bush.py/tree.py by being mineral (cube-
based, not rounded spheres) and grey rather than green.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

ROCK_COLOR = (0.5, 0.48, 0.45)
ROCK_DARK_COLOR = (0.36, 0.35, 0.33)


def build():
    rock_mat = flat_material("Rock", ROCK_COLOR)
    rock_dark_mat = flat_material("RockDark", ROCK_DARK_COLOR)

    part(bpy.ops.mesh.primitive_cube_add, rock_mat, (0, 0, 0.14), scale=(0.24, 0.2, 0.14), size=1.0, rotation=(0, 0, 0.3))
    part(bpy.ops.mesh.primitive_cube_add, rock_dark_mat, (0.15, -0.08, 0.08), scale=(0.14, 0.12, 0.08), size=1.0, rotation=(0, 0, -0.4))
