"""assets/zombies/zombie_0_<facing>.png — variant 0 of ZombieVisuals.VARIANT_COUNT.

The upright shambler: compact, roughly as wide as it is deep, both arms reaching.
The baseline the other two are read against.

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

FLESH = (0.478, 0.518, 0.396)
FLESH_DARK = (0.325, 0.369, 0.271)
RAG = (0.243, 0.259, 0.196)  # A dark note in the flesh family, not neutral grey: a
# grey patch on a green body reads as a box dropped on it rather than as cloth.

Z = 0.28
ARM_Z = Z + 0.105

def build():
    flesh = flat_material("Flesh", FLESH)
    flesh_dark = flat_material("FleshDark", FLESH_DARK)
    rag = flat_material("Rag", RAG)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (0.0, 0.0, Z),
         rotation=(0.0, 0.0, 0.26), scale=(0.235, 0.190, 0.105),
         segments=16, ring_count=9, radius=1.0)
    # Rags: two irregular flaps, the only hard dark shapes, so the outline never
    # closes into a clean oval.
    part(bpy.ops.mesh.primitive_cube_add, rag, (-0.06, -0.115, Z + 0.100),
         rotation=(0.0, 0.0, 0.42), scale=(0.105, 0.070, 0.010), size=1.0)
    part(bpy.ops.mesh.primitive_cube_add, rag, (0.125, -0.165, Z + 0.096),
         rotation=(0.0, 0.0, -0.30), scale=(0.082, 0.058, 0.010), size=1.0)

    # Arms reaching forward, unequal length and angle.
    for side, hand_at, radius in ((-1.0, (-0.205, 0.395, ARM_Z), 0.044),
                                  (1.0, (0.230, 0.315, ARM_Z), 0.041)):
        shoulder = (side * 0.185, 0.020, ARM_Z)
        elbow = (side * 0.235, 0.205, ARM_Z)
        limb(flesh_dark, [shoulder, elbow, hand_at], [radius, radius * 0.86])
        hand(flesh, hand_at, radius=0.040, fingers=3, spread=0.52)

    # Head: bare, small, lolled off-centre and forward.
    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (0.055, 0.150, Z + 0.135),
         rotation=(0.0, 0.0, 0.30), scale=(0.088, 0.080, 0.062),
         segments=12, ring_count=7, radius=1.0)
