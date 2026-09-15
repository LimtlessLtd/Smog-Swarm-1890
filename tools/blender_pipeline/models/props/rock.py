"""assets/props/rock.png — scattered decorative prop. An angular grey boulder
cluster, distinct from bush.py/tree.py by being mineral (faceted, not a rounded
canopy) and grey rather than green.

Re-authored 2026-09-15 for the straight-down camera. The old version was two
rotated cubes, which at 75 degrees showed three faces each and read as rock. At
90 degrees a cube shows ONE face, so the whole prop rendered as two flat grey
quadrilaterals with no form at all — the prop equivalent of what happened to the
buildings. Boulders are now low faceted domes of differing size, which keep a
lit/shadow split from directly above, plus a scree skirt that breaks the outline
so the cluster does not read as a smooth pebble.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

ROCK_COLOR = (0.522, 0.510, 0.482)
ROCK_DARK_COLOR = (0.376, 0.365, 0.345)
SCREE_COLOR = (0.435, 0.424, 0.400)

# (x, y, radius, flatten, rotation) — three unequal boulders, biggest off-centre
# so the cluster has a clear dominant mass rather than reading as a rosette.
BOULDERS = (
    (-0.04, 0.02, 0.26, 0.62, 0.30),
    (0.20, -0.14, 0.16, 0.58, -0.45),
    (-0.20, -0.18, 0.11, 0.55, 0.80),
)


def build():
    rock_mat = flat_material("Rock", ROCK_COLOR)
    rock_dark_mat = flat_material("RockDark", ROCK_DARK_COLOR)
    scree_mat = flat_material("Scree", SCREE_COLOR)

    for i, (x, y, radius, flatten, rotation) in enumerate(BOULDERS):
        # Low segment count on purpose: 7 sides keeps hard facets, so Freestyle
        # strokes real creases across the top instead of one smooth silhouette.
        part(bpy.ops.mesh.primitive_uv_sphere_add,
             rock_mat if i % 2 == 0 else rock_dark_mat,
             (x, y, radius * flatten * 0.5),
             rotation=(0.0, 0.0, rotation),
             scale=(1.0, 0.86, flatten), segments=7, ring_count=4, radius=radius)

    # Scree: small chips around the base, so the cluster has a broken edge.
    for i in range(6):
        angle = math.tau * i / 6.0 + 0.4
        part(bpy.ops.mesh.primitive_cube_add, scree_mat,
             (math.cos(angle) * 0.30, math.sin(angle) * 0.26, 0.022),
             rotation=(0.0, 0.0, angle * 1.7),
             scale=(0.075, 0.060, 0.040), size=1.0)
