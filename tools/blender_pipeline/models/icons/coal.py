"""assets/icons/coal.png — resource has no icon today (ResourceVisuals._icon_key
COAL -> "coal", no matching PNG exists yet, ResourceBarView falls back to
text-only). First prototype asset for the Blender pipeline: small enough to
validate the whole rig (camera/outline/transparency/Godot import) without
committing to a style choice across all ~65 remaining assets first.
"""

import bpy
import random
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material  # noqa: E402

# Deterministic across re-renders — no wall-clock/random-seed drift between runs.
random.seed(1)

COAL_DARK = (0.02, 0.02, 0.03)
COAL_LIGHTER = (0.06, 0.05, 0.06)  # faint tonal break between lumps, still reads as "black coal"


def build():
    mat_dark = flat_material("CoalDark", COAL_DARK)
    mat_light = flat_material("CoalLighter", COAL_LIGHTER)

    # A small irregular pile: a handful of scaled/rotated icospheres clustered at
    # the origin. Icosphere (not UV sphere) so Freestyle's outline traces a faceted
    # rock-like silhouette instead of a perfectly round blob.
    lumps = [
        # (x, y, z, scale, subdiv)
        (0.0, 0.0, 0.0, 0.55, 1),
        (0.35, 0.15, 0.05, 0.4, 1),
        (-0.3, 0.25, 0.0, 0.35, 1),
        (0.1, -0.3, 0.05, 0.38, 1),
        (-0.15, -0.15, 0.25, 0.3, 1),
    ]

    for i, (x, y, z, scale, subdiv) in enumerate(lumps):
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=subdiv, radius=1.0, location=(x, y, z)
        )
        obj = bpy.context.active_object
        obj.scale = (scale, scale * random.uniform(0.85, 1.1), scale * random.uniform(0.8, 1.0))
        obj.rotation_euler = (
            random.uniform(0, 6.28),
            random.uniform(0, 6.28),
            random.uniform(0, 6.28),
        )
        bpy.ops.object.shade_flat()
        obj.data.materials.append(mat_light if i % 2 else mat_dark)
