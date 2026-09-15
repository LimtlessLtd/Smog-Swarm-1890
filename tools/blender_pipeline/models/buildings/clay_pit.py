"""assets/buildings/clay_pit.png — GameEnums.BuildingType.CLAY_PIT.

Tier 0 open working. The one extraction site with NO headframe: a clay pit is a
hole in the ground, so it is drawn as nested terraces stepping down to a dark
sump. That makes it the family member reading as a VOID where every other one
reads as a structure, which is the real differentiation — at map zoom
ochre-versus-rust is a far weaker signal than hole-versus-tower.

Re-authored 2026-09-15 for the straight-down camera, on the extraction family's
ground/path system (see coal_pithead.py for the reference model, and
render_common's organic-ground block for why the old full-quad plate went).
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ground_patch, path, family_materials,
)

ORE_COLOR = (0.639, 0.463, 0.263)  # wet clay ochre


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    clay_mat = flat_material("Clay", ORE_COLOR)
    dirt_mat = flat_material("Dirt", (0.451, 0.376, 0.278), alpha=0.82)
    track_mat = flat_material("Track", (0.565, 0.478, 0.361), alpha=0.92)

    ground_patch(dirt_mat, (-0.06, 0.02, 0.002), radius_x=0.56, radius_y=0.50,
                 sides=15, jitter=0.22, seed=401, name="Workings")

    # Three nested terraces stepping down, each its own irregular patch at a
    # darker tone, so the pit reads as depth rather than as a target.
    for i, (rx, ry, shade) in enumerate(((0.40, 0.36, 0.86), (0.28, 0.25, 0.68),
                                         (0.16, 0.14, 0.46))):
        bench = flat_material("Bench%d" % i, tuple(c * shade for c in ORE_COLOR))
        ground_patch(bench, (-0.10, 0.04, 0.004 + i * 0.002), radius_x=rx, radius_y=ry,
                     sides=13 - i, jitter=0.16, seed=411 + i * 7, name="Bench%d" % i)
    # Sump at the bottom — standing water, the darkest thing on the site.
    ground_patch(flat_material("Sump", (0.184, 0.188, 0.180)), (-0.10, 0.04, 0.012),
                 radius_x=0.09, radius_y=0.08, sides=9, jitter=0.20, seed=431, name="Sump")

    # Haul ramp climbing out of the pit to the drying floor.
    path(track_mat, [(-0.10, -0.08), (0.10, -0.20), (0.30, -0.30), (0.46, -0.34)],
         width=0.11, seed=437)

    # Drying floor: clay barrows laid out in rows to weather.
    ground_patch(dirt_mat, (0.44, -0.34, 0.003), radius_x=0.22, radius_y=0.18,
                 sides=10, jitter=0.24, seed=443, name="DryingFloor")
    for ix in range(3):
        for iy in range(2):
            part(bpy.ops.mesh.primitive_cube_add, clay_mat,
                 (0.34 + ix * 0.075, -0.40 + iy * 0.070, 0.034),
                 scale=(0.055, 0.050, 0.030), size=1.0)

    # Windlass shed at the pit head — kept small so the hole stays dominant.
    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (0.34, 0.26, 0.07),
         scale=(0.24, 0.22, 0.12), size=1.0)
    hip_roof(timber_mat, (0.34, 0.26, 0.13), width=0.22, depth=0.20,
             height=0.11, ridge_fraction=0.45)
