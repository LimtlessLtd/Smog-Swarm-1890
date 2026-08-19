"""assets/props/tree.png — scattered decorative prop, seen from directly
above.

Rebuilt for TerrainDetailView, which fills a woodland polygon with hundreds
of these. The previous version was ONE low-poly sphere over a trunk: from the
overhead camera every tree in a forest was the same pale flat decagon, and a
wood rendered as confetti rather than as canopy.

What reads as a tree from above is a lobed CROWN, so the canopy is five
overlapping spheres of differing size, height and tone. The overlaps give an
irregular silhouette and internal shading breaks, which is what the eye picks
up as foliage; a single sphere has neither. Deliberately not symmetric --
identical lobes would rebuild the same disc.

The trunk stays, though almost none of it is visible from overhead: it puts a
dark core at the crown's centre, which is what stops the whole shape reading
as a solid blob.

Colours are darker than they render. flat_material() is a two-tone toon ramp
whose LIT tone sits well above the base colour, so a mid-green base comes out
sage; these are chosen so the lit tone lands on the deep green of a British
broadleaf wood rather than above it.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

TRUNK_COLOR = (0.19, 0.12, 0.07)
CANOPY_COLOR = (0.13, 0.26, 0.09)
CANOPY_LIGHT_COLOR = (0.19, 0.34, 0.12)
CANOPY_DARK_COLOR = (0.08, 0.17, 0.06)

## (x, y, radius, height, material index into the list below). Sizes and
## offsets are hand-placed rather than generated: the shape has to be
## irregular but still centred and roughly circular overall, which a random
## scatter of this few lobes does not reliably give.
_LOBES = [
	(0.00, 0.00, 0.20, 0.52, 0),
	(-0.13, 0.08, 0.15, 0.47, 1),
	(0.12, 0.11, 0.14, 0.48, 0),
	(0.14, -0.10, 0.13, 0.44, 2),
	(-0.10, -0.13, 0.12, 0.45, 2),
]


def build():
	trunk_mat = flat_material("Trunk", TRUNK_COLOR)
	mats = [
		flat_material("Canopy", CANOPY_COLOR),
		flat_material("CanopyLight", CANOPY_LIGHT_COLOR),
		flat_material("CanopyDark", CANOPY_DARK_COLOR),
	]

	part(bpy.ops.mesh.primitive_cone_add, trunk_mat, (0, 0, 0.18),
		radius1=0.05, radius2=0.035, depth=0.36, vertices=8)

	for x, y, radius, height, mat_index in _LOBES:
		# Flattened on Z: a full sphere's silhouette from overhead is its
		# equator, so squashing it keeps the same footprint while bringing the
		# shaded upper surface -- the part that actually reads as foliage --
		# into view.
		part(bpy.ops.mesh.primitive_uv_sphere_add, mats[mat_index], (x, y, height),
			scale=(1.0, 1.0, 0.62), segments=16, ring_count=9, radius=radius)

	# A few small dark clusters set just inside the crown's edge, breaking the
	# outline so neighbouring trees in a dense wood do not tile into a smooth
	# mat of identical circles.
	for i in range(6):
		angle = i * (math.tau / 6.0) + 0.4
		part(bpy.ops.mesh.primitive_uv_sphere_add, mats[2],
			(math.cos(angle) * 0.19, math.sin(angle) * 0.19, 0.44),
			scale=(1.0, 1.0, 0.55), segments=10, ring_count=6, radius=0.075)
