"""assets/props/bush.png — scattered decorative prop, seen from directly
above. A low, wide, trunk-less foliage cluster, distinct from tree.py by
having no stem at all and sitting directly on the ground.

Rebuilt alongside tree.py for the same reason (see that file): three
low-segment spheres read as one flat blob from overhead at the density
TerrainDetailView scatters heathland at. This is a wider, flatter, more
broken-up cluster, in a yellower green than the tree's -- heather and gorse
against broadleaf canopy, which is the distinction the two are carrying on
screen.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

BUSH_COLOR = (0.20, 0.28, 0.09)
BUSH_LIGHT_COLOR = (0.28, 0.35, 0.12)
BUSH_DARK_COLOR = (0.12, 0.19, 0.06)


def build():
	mats = [
		flat_material("Bush", BUSH_COLOR),
		flat_material("BushLight", BUSH_LIGHT_COLOR),
		flat_material("BushDark", BUSH_DARK_COLOR),
	]

	# Flatter than the tree's lobes (0.45 against 0.62): a shrub is a mound,
	# and the squash is what keeps it from reading as a small tree when the
	# two are scattered side by side on the same ground.
	for i in range(7):
		angle = i * (math.tau / 7.0) + 0.9
		radius = 0.10 + 0.035 * ((i * 3) % 4)
		distance = 0.0 if i == 0 else 0.13
		part(bpy.ops.mesh.primitive_uv_sphere_add, mats[i % 3],
			(math.cos(angle) * distance, math.sin(angle) * distance, radius * 0.55),
			scale=(1.15, 1.0, 0.45), segments=12, ring_count=7, radius=radius)
