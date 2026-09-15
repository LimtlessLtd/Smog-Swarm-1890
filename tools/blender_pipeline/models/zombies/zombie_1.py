"""assets/zombies/zombie_1_<facing>.png — variant 1 of ZombieVisuals.VARIANT_COUNT.

The crawler: LONG and LOW, a sprawl roughly 2.5x longer than it is wide, with one
arm thrown far forward and the legs trailing.

The old version was pitched nearly horizontal for a 58-degree camera and, shot
straight down, read as a barrel lying on its side. Straight down is the angle a
crawler actually wants.

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

FLESH = (0.514, 0.553, 0.416)
FLESH_DARK = (0.345, 0.396, 0.278)
RAG = (0.243, 0.259, 0.196)  # A dark note in the flesh family, not neutral grey: a
# grey patch on a green body reads as a box dropped on it rather than as cloth.

Z = 0.28
ARM_Z = Z + 0.105

def build():
    flesh = flat_material("Flesh", FLESH)
    flesh_dark = flat_material("FleshDark", FLESH_DARK)
    rag = flat_material("Rag", RAG)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (0.0, 0.02, Z - 0.06),
         rotation=(0.0, 0.0, 0.14), scale=(0.165, 0.335, 0.085),
         segments=16, ring_count=9, radius=1.0)
    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh_dark, (0.02, -0.325, Z - 0.075),
         scale=(0.140, 0.140, 0.070), segments=12, ring_count=7, radius=1.0)
    part(bpy.ops.mesh.primitive_cube_add, rag, (-0.02, -0.135, Z + 0.012),
         rotation=(0.0, 0.0, 0.30), scale=(0.098, 0.130, 0.010), size=1.0)

    # Legs trailing, both bent back and unequal.
    for side, knee, foot in ((-1.0, (-0.165, -0.455, Z - 0.09), (-0.245, -0.610, Z - 0.09)),
                             (1.0, (0.145, -0.470, Z - 0.09), (0.115, -0.645, Z - 0.09))):
        limb(flesh_dark, [(side * 0.105, -0.325, Z - 0.09), knee, foot], [0.046, 0.039])

    # One arm thrown far forward, clawing; the other tucked short under the chest.
    limb(flesh_dark, [(-0.130, 0.175, Z + 0.02), (-0.215, 0.370, Z + 0.02),
                      (-0.180, 0.585, Z + 0.02)], [0.044, 0.037])
    hand(flesh, (-0.180, 0.585, Z + 0.02), radius=0.040, fingers=3, spread=0.55)
    limb(flesh_dark, [(0.150, 0.150, Z + 0.02), (0.255, 0.240, Z + 0.02),
                      (0.215, 0.360, Z + 0.02)], [0.042, 0.035])
    hand(flesh, (0.215, 0.360, Z + 0.02), radius=0.038, fingers=3, spread=0.50)

    part(bpy.ops.mesh.primitive_uv_sphere_add, flesh, (-0.045, 0.395, Z + 0.035),
         rotation=(0.0, 0.0, -0.25), scale=(0.088, 0.082, 0.058),
         segments=12, ring_count=7, radius=1.0)
