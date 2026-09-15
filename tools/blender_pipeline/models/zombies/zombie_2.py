"""assets/zombies/zombie_2_<facing>.png — variant 2 of ZombieVisuals.VARIANT_COUNT.

The bloated one: WIDE and heavy, broader across than it is deep, with short stubby
arms that barely clear the bulk and a split gut — the only warm colour on any
zombie, so this is the variant with a red mark on it.

Three variants, three footprints: compact / long / wide. At 17 px those are three
different blobs where three sets of facial detail would have been three identical
ones.

Kept SIMPLE on the user's call ("keep them simple and readable"): the units got
an anatomy and detail pass, the zombies deliberately did not. At the size a horde
is actually drawn, a zombie is a green mass, and the design effort goes into the
three variants having three different FOOTPRINTS rather than into detail nobody
resolves. They do use the same bone()/limb() chain as the units, because "arms
that arent properly joined up" was a defect everywhere, not a style choice.

Shared rules against a unit silhouette: no headgear, arms reaching FORWARD past
the head, asymmetric, and the one hue no unit uses.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, bone, limb, hand  # noqa: E402

FLESH = (0.435, 0.478, 0.349)
FLESH_DARK = (0.298, 0.341, 0.235)
RAG = (0.243, 0.259, 0.196)  # A dark note in the flesh family, not neutral grey: a
# grey patch on a green body reads as a box dropped on it rather than as cloth.

Z = 0.28
ARM_Z = Z + 0.105

BURST = (0.435, 0.192, 0.176)


def build():
    flesh = flat_material("Flesh", FLESH)
    flesh_dark = flat_material("FleshDark", FLESH_DARK)
    rag = flat_material("Rag", RAG)
    burst = flat_material("Burst", BURST)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (0.0, -0.02, Z),
         rotation=(0.0, 0.0, -0.14), scale=(0.375, 0.265, 0.125),
         segments=18, ring_count=9, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, burst, (0.045, 0.100, Z + 0.120),
         rotation=(0.0, 0.0, 0.30), scale=(0.155, 0.090, 0.022),
         segments=12, ring_count=7, radius=1.0)
    part(bpy.ops.mesh.primitive_cube_add, rag, (0.095, -0.205, Z + 0.112),
         rotation=(0.0, 0.0, -0.22), scale=(0.125, 0.072, 0.010), size=1.0)

    # Short stubby arms — this one can hardly extend at all.
    for side, hand_at in ((-1.0, (-0.415, 0.215, ARM_Z)), (1.0, (0.430, 0.185, ARM_Z))):
        shoulder = (side * 0.275, 0.020, ARM_Z)
        elbow = (side * 0.375, 0.115, ARM_Z)
        limb(flesh_dark, [shoulder, elbow, hand_at], [0.052, 0.044])
        hand(flesh, hand_at, radius=0.044, fingers=3, spread=0.48)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (-0.060, 0.210, Z + 0.150),
         rotation=(0.0, 0.0, 0.18), scale=(0.090, 0.082, 0.058),
         segments=12, ring_count=7, radius=1.0)
