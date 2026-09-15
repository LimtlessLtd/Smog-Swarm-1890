"""assets/props/reed.png — scattered decorative prop (wetland flavour).

Re-authored 2026-09-15 for the straight-down camera. The old model leaned its
blades hard off vertical (0.5-0.8 rad) specifically so a 75-degree camera would
not foreshorten them into dots — its own comment says so. At 90 degrees that
same tilt lays them flat, and the shipped prop read as a heap of horizontal logs
rather than reeds.

Straight down, a reed bed cannot be drawn as blades at all: a vertical stem
projects to a dot however tall it is. So this is now drawn as what a reed bed
actually looks like from the air — a ragged clump of wet ground with stem
clusters scattered over it and a few seed heads — and the prop's job of being
"the thin wetland one" is carried by the clump's broken outline against bush.py's
and tree.py's solid round canopies.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, ground_patch  # noqa: E402

REED_COLOR = (0.545, 0.604, 0.310)
REED_DARK_COLOR = (0.404, 0.475, 0.239)
MUD_COLOR = (0.314, 0.325, 0.239)
TIP_COLOR = (0.451, 0.325, 0.180)

# (x, y, radius, flatten) — clumps of differing size, deliberately not a ring.
CLUMPS = (
    (-0.10, 0.06, 0.20, 0.42),
    (0.16, 0.00, 0.15, 0.38),
    (-0.02, -0.20, 0.13, 0.34),
    (0.22, 0.22, 0.10, 0.30),
)


def build():
    reed_mat = flat_material("Reed", REED_COLOR)
    reed_dark_mat = flat_material("ReedDark", REED_DARK_COLOR)
    mud_mat = flat_material("Mud", MUD_COLOR, alpha=0.82)
    tip_mat = flat_material("Tip", TIP_COLOR)

    # Wet ground the bed stands in, translucent so terrain reads through.
    ground_patch(mud_mat, (0.02, 0.0, 0.002), radius_x=0.36, radius_y=0.32,
                 sides=12, jitter=0.30, seed=77, name="WetGround")

    for i, (x, y, radius, flatten) in enumerate(CLUMPS):
        part(bpy.ops.mesh.primitive_uv_sphere_add,
             reed_mat if i % 2 == 0 else reed_dark_mat,
             (x, y, radius * flatten * 0.5),
             scale=(1.0, 0.88, flatten), segments=9, ring_count=5, radius=radius)

    # Seed heads: a few short stems standing clear of the clumps. Vertical
    # cylinders read as small dots from here, which is exactly right for seed
    # heads and exactly wrong for blades — hence drawing only these.
    for i in range(5):
        angle = math.tau * i / 5.0 + 0.9
        part(bpy.ops.mesh.primitive_cylinder_add, tip_mat,
             (0.02 + math.cos(angle) * 0.24, math.sin(angle) * 0.21, 0.14),
             radius=0.028, depth=0.10)
