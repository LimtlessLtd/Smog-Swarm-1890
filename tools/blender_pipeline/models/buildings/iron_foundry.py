"""assets/buildings/cast_iron_foundry.png — GameEnums.BuildingType.IRON_FOUNDRY
(BuildingVisuals._texture_key keeps the "cast_iron_foundry" art key).

Re-authored 2026-09-15 for the straight-down camera, and the heavy-industry
family's reference model. Overhead the old version was a small grey box and an
orange cylinder lost inside a ring of tiny fence posts that occupied most of the
frame. The heavy family signature is the glowing tap-hole circle plus large
chimney discs on dark ash ground: the only saturated orange on the building
roster, so a foundry is findable at map zoom by colour alone.

Ground is ash and clinker trodden into irregular patches with a haul road
between the casting shed and the furnace, rather than the slab the first slice
used — see render_common's organic-ground block for the user note behind that.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, roof_vent, ground_patch, path, family_materials,
)

SHED_XY = (-0.24, 0.02)
FURNACE_XY = (0.32, 0.18)


def build():
    ash_mat, roof_mat, glow_mat = family_materials("heavy")
    iron_mat = flat_material("Iron", (0.475, 0.490, 0.515))
    # Ash is dark and nearly opaque — a foundry yard really is covered — but the
    # edge is ragged and the corners of the frame stay clear.
    ground_mat = flat_material("Ash", (0.176, 0.169, 0.161), alpha=0.88)
    clinker_mat = flat_material("Clinker", (0.345, 0.325, 0.298), alpha=0.92)  # Must sit clear of the ash it crosses; at 0.243 the haul road was invisible against it.

    ground_patch(ground_mat, (SHED_XY[0], SHED_XY[1], 0.002), radius_x=0.46,
                 radius_y=0.44, sides=13, jitter=0.22, seed=3, name="ShedYard")
    ground_patch(ground_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.002), radius_x=0.32,
                 radius_y=0.32, sides=12, jitter=0.26, seed=19, name="FurnaceYard")
    ground_patch(ground_mat, (-0.08, -0.40, 0.002), radius_x=0.34, radius_y=0.19,
                 sides=11, jitter=0.30, seed=27, name="MouldFloor")

    # Haul road shed -> furnace, and a spur down to the mould floor.
    path(clinker_mat, [SHED_XY, (0.04, 0.12), FURNACE_XY], width=0.13, seed=5)
    path(clinker_mat, [(-0.22, -0.16), (-0.14, -0.30), (-0.08, -0.38)],
         width=0.10, seed=11)

    # Casting shed: a long hipped roof with a continuous ridge vent, the shape
    # a real foundry shows from the air.
    part(bpy.ops.mesh.primitive_cube_add, iron_mat, (SHED_XY[0], SHED_XY[1], 0.09),
         scale=(0.58, 0.62, 0.16), size=1.0)
    hip_roof(roof_mat, (SHED_XY[0], SHED_XY[1], 0.17), width=0.54, depth=0.58,
             height=0.17, ridge_fraction=0.60)
    part(bpy.ops.mesh.primitive_cube_add, iron_mat, (SHED_XY[0], SHED_XY[1], 0.335),
         scale=(0.28, 0.08, 0.03), size=1.0)

    # Cupola furnace: the tap hole is the family signature and the brightest
    # thing on the model. Sunk inside an iron collar so it reads as a hot
    # opening rather than an orange lid.
    part(bpy.ops.mesh.primitive_cylinder_add, iron_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.20),
         radius=0.20, depth=0.38)
    part(bpy.ops.mesh.primitive_cylinder_add, glow_mat, (FURNACE_XY[0], FURNACE_XY[1], 0.40),
         radius=0.14, depth=0.03)

    # Two chimney stacks of different diameters — a count and a size the other
    # heavy-industry buildings vary, so foundry/steelworks/furnace differ by
    # stack arrangement rather than needing new colours.
    roof_vent(iron_mat, (0.30, -0.26, 0.22), radius=0.095, height=0.42)
    roof_vent(iron_mat, (0.08, -0.34, 0.18), radius=0.062, height=0.34)

    # Pig-iron moulds laid out on the sand floor.
    for i in range(4):
        part(bpy.ops.mesh.primitive_cube_add, iron_mat,
             (-0.26 + i * 0.055, -0.40, 0.030), scale=(0.026, 0.12, 0.020), size=1.0)
