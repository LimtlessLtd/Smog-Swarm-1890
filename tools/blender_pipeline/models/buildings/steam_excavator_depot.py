"""assets/buildings/steam_excavator_depot.png — GameEnums.BuildingType.
STEAM_EXCAVATOR_DEPOT, Tier 4 Industry & Extraction. A parked steam
excavator with a large scoop arm — the scoop-arm silhouette is unique to
this building, a real machine rather than a mine/shed structure.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import flat_material, part, wheel  # noqa: E402

HULL_COLOR = (0.44, 0.32, 0.2)
TRACK_COLOR = (0.16, 0.15, 0.14)
SCOOP_COLOR = (0.5, 0.48, 0.46)


def build():
    hull_mat = flat_material("Hull", HULL_COLOR)
    track_mat = flat_material("Track", TRACK_COLOR)
    scoop_mat = flat_material("Scoop", SCOOP_COLOR)

    for side in (-0.24, 0.24):
        part(bpy.ops.mesh.primitive_cube_add, track_mat, (side, 0, 0.08), scale=(0.08, 0.55, 0.1), size=1.0)

    part(bpy.ops.mesh.primitive_cylinder_add, hull_mat, (0, -0.05, 0.24), radius=0.2, depth=0.2)

    # Boom arm + scoop, angled forward-down.
    part(bpy.ops.mesh.primitive_cube_add, hull_mat, (0, 0.25, 0.35),
         scale=(0.07, 0.4, 0.07), size=1.0, rotation=(0.5, 0, 0))
    part(bpy.ops.mesh.primitive_cube_add, scoop_mat, (0, 0.5, 0.14),
         scale=(0.16, 0.16, 0.1), size=1.0, rotation=(0.6, 0, 0))
