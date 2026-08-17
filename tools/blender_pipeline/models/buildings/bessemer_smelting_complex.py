"""assets/buildings/bessemer_smelting_complex.png — GameEnums.BuildingType.
BESSEMER_SMELTING_COMPLEX, Tier 5 Industry & Extraction. An upright
onion-domed converter vessel with a small pour-spout horn — distinct from
every straight-chimney furnace on the roster by its rounded dome shape.

Third pass. First pass (tilted sphere+cone, symmetric sparks) read as a
face. Second pass (tilted cylinder+cone) projected into ambiguous
overlapping crescents from this pipeline's steep top-down angle — tilting
primitive geometry for a "pouring" effect just doesn't read at this camera
angle, confirmed on two separate real renders. This pass keeps the vessel
upright (clean, unambiguous circular silhouette from directly above) and
does the differentiation with a small asymmetric spout nub instead of
trying to convey "tilt" through the whole vessel's own rotation.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part  # noqa: E402

VESSEL_COLOR = (0.65, 0.543, 0.436)
BASE_COLOR = (0.381, 0.341, 0.301)
SPARK_COLOR = (1.0, 0.688, 0.0)


def build():
    vessel_mat = flat_material("Vessel", VESSEL_COLOR)
    base_mat = flat_material("Base", BASE_COLOR)
    spark_mat = flat_material("Spark", SPARK_COLOR)

    part(bpy.ops.mesh.primitive_cylinder_add, base_mat, (0, 0, 0.06), scale=(1.0, 1.0, 0.3), radius=0.26, depth=0.4)

    # Upright onion-domed vessel: cylinder body + dome cap, straight up —
    # a clean, unambiguous silhouette from this pipeline's steep camera angle.
    part(bpy.ops.mesh.primitive_cylinder_add, vessel_mat, (0, 0, 0.35), radius=0.2, depth=0.4)
    part(bpy.ops.mesh.primitive_uv_sphere_add, vessel_mat, (0, 0, 0.58), scale=(1.0, 1.0, 0.7), segments=10, ring_count=6, radius=0.2)

    # Pour-spout horn: a single small cone jutting out to one side near the
    # top — asymmetric on purpose, the differentiating detail instead of a
    # whole-vessel tilt.
    part(bpy.ops.mesh.primitive_cone_add, vessel_mat, (0.32, 0.1, 0.5),
         rotation=(1.2, 0, 0.6), radius1=0.07, radius2=0.02, depth=0.24)

    # Sparks trailing from the spout tip only — one small offset cluster,
    # not a symmetric pair.
    for x, y, z in [(0.44, 0.16, 0.42), (0.48, 0.2, 0.36)]:
        part(bpy.ops.mesh.primitive_uv_sphere_add, spark_mat, (x, y, z), segments=6, ring_count=4, radius=0.03)
