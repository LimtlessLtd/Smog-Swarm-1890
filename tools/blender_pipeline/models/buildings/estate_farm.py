"""assets/buildings/estate_farm.png — GameEnums.BuildingType.ESTATE_FARM.

Re-authored 2026-09-15 for the straight-down camera, and the agriculture family's
reference model. This family survived the angle change best — a field with
furrows already is a top-down shape — but the old version put a rotated barn box
in the middle of a circular green disc.

The field is now an irregular ground_patch() rather than a rectangle or a circle:
a ploughed field has a boundary that follows the land, and it is the one family
where the ground IS the building, so a hard square edge was most obviously wrong
here. A cart track runs from the field gate through the yard to the barn and on
to the stock pen.
"""

import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, furrows, ground_patch, path, family_materials,
)

BARN_XY = (0.30, 0.20)
SILO_XY = (0.36, -0.24)
PEN_XY = (0.04, -0.34)


def build():
    field_mat, barn_mat, cream_mat = family_materials("agriculture")
    # The crop is translucent so the terrain's own green still modulates it —
    # a farm should look like worked ground, not a green tile dropped on grass.
    crop_mat = flat_material("Crop", (0.486, 0.549, 0.243), alpha=0.80)
    yard_mat = flat_material("Yard", (0.451, 0.412, 0.333), alpha=0.86)
    track_mat = flat_material("Track", (0.639, 0.576, 0.463), alpha=0.92)  # Pale chalk cart track, well clear of the yard tone.
    soil_mat = flat_material("Soil", (0.361, 0.286, 0.192), alpha=0.95)  # Ploughing is turned earth. Drawn in the barn's terracotta it read as red stripes painted on grass.

    # Ploughed field, irregular edged, occupying the left of the site.
    ground_patch(crop_mat, (-0.30, 0.02, 0.002), radius_x=0.42, radius_y=0.46,
                 sides=14, jitter=0.18, seed=41, name="Field")
    # Farmyard, its own patch, overlapping the field slightly at the gate.
    ground_patch(yard_mat, (0.30, -0.02, 0.003), radius_x=0.34, radius_y=0.42,
                 sides=12, jitter=0.22, seed=53, name="Farmyard")

    # Furrows sit on the field only; furrows() takes an x centre so they stay
    # clear of the yard rather than running out across it.
    furrows(soil_mat, count=7, width=0.52, z=0.006, spacing=0.095, x=-0.30)

    # Cart track: field gate -> yard -> barn, with a branch to the stock pen.
    path(track_mat, [(-0.62, -0.22), (-0.22, -0.16), (0.14, -0.06), (BARN_XY[0], 0.06)],
         width=0.10, seed=61)
    path(track_mat, [(0.16, -0.10), PEN_XY], width=0.08, seed=67)

    # Barn: terracotta hip roof, the family's roof colour.
    part(bpy.ops.mesh.primitive_cube_add, cream_mat, (BARN_XY[0], BARN_XY[1], 0.09),
         scale=(0.36, 0.42, 0.15), size=1.0)
    hip_roof(barn_mat, (BARN_XY[0], BARN_XY[1], 0.165), width=0.34, depth=0.40,
             height=0.16, ridge_fraction=0.52)

    # Silo: the agriculture signature. A domed cylinder reads overhead as a
    # bright hard-edged circle, and no other family has one.
    part(bpy.ops.mesh.primitive_cylinder_add, cream_mat, (SILO_XY[0], SILO_XY[1], 0.20),
         radius=0.14, depth=0.40)
    part(bpy.ops.mesh.primitive_uv_sphere_add, cream_mat, (SILO_XY[0], SILO_XY[1], 0.40),
         scale=(1.0, 1.0, 0.55), segments=14, ring_count=7, radius=0.14)

    # Stock pen: trodden ground inside a run of posts, not a rail frame. Four
    # solid rails read overhead as an empty black-edged box — the enclosure has
    # to be legible from what is INSIDE it, since a fence line is sub-pixel at
    # map zoom.
    ground_patch(yard_mat, (PEN_XY[0], PEN_XY[1], 0.004), radius_x=0.17,
                 radius_y=0.15, sides=10, jitter=0.12, seed=59, name="PenGround")
    for i in range(10):
        angle = math.tau * i / 10.0
        part(bpy.ops.mesh.primitive_cylinder_add, cream_mat,
             (PEN_XY[0] + math.cos(angle) * 0.16, PEN_XY[1] + math.sin(angle) * 0.14, 0.045),
             radius=0.017, depth=0.09)
