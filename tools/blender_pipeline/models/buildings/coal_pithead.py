"""assets/buildings/coal_pithead.png — GameEnums.BuildingType.COAL_MINE.

Re-authored 2026-09-15 for the straight-down camera, and the extraction family's
reference model. The old model was a tan mound with an angled headframe, which
overhead collapsed into a featureless blob — and coal_pithead, iron_ore_mine,
deep_coal_shafts and sulfur_mine were all that same blob, separated only by a few
specks of ore colour.

The extraction signature is the winding-gear wheel seen flat-on as a large ring
directly over a black shaft square. Per-mine identity is then the ore colour on
the spoil heaps and the number of shafts, not a different building.

Ground is a scatter of ground_patch() blobs joined by path() tramways rather than
one yard_plate() rectangle, per the user's note that the first slice was "all
exact squares with no transparency anywhere". A colliery is the clearest case
for it: the real thing IS a few structures standing in worn ground with tub
roads running between them, so the gaps carry terrain through and the tramways
are what tie the site together.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, ring, ground_patch, path, family_materials,
)

ORE_COLOR = (0.105, 0.098, 0.094)  # coal — the per-mine variable across this family

SHAFT_XY = (-0.16, 0.12)
ENGINE_XY = (0.38, 0.16)
HEAP_XY = ((-0.46, -0.40), (-0.10, -0.46), (0.26, -0.38))


def build():
    spoil_mat, timber_mat, shaft_mat = family_materials("extraction")
    ore_mat = flat_material("Ore", ORE_COLOR)
    # Ground sits under everything at alpha < 1 so the terrain's own tone still
    # reads through the worn dirt instead of being replaced by it.
    dirt_mat = flat_material("Dirt", (0.404, 0.337, 0.235), alpha=0.82)
    track_mat = flat_material("Track", (0.302, 0.251, 0.180), alpha=0.90)

    # Worn ground, one blob per occupied area rather than a single slab. Seeds
    # are fixed so the ragged edges are identical on every re-render.
    ground_patch(dirt_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.002),
                 radius_x=0.40, radius_y=0.38, seed=11, name="PitYard")
    ground_patch(dirt_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.002),
                 radius_x=0.30, radius_y=0.30, seed=23, name="EngineYard")
    for i, (hx, hy) in enumerate(HEAP_XY):
        ground_patch(dirt_mat, (hx, hy, 0.002), radius_x=0.22, radius_y=0.17,
                     seed=31 + i * 7, jitter=0.30, name="SpoilGround%d" % i)

    # Tub roads: shaft to engine house, and shaft out to each heap. These are
    # the "paths between the various different buildings" — they also fill the
    # gaps between patches, so the site reads as one place with holes in it
    # rather than as three unrelated stains.
    path(track_mat, [SHAFT_XY, (0.10, 0.15), ENGINE_XY], width=0.11, seed=3)
    for i, heap in enumerate(HEAP_XY):
        path(track_mat, [SHAFT_XY, ((SHAFT_XY[0] + heap[0]) * 0.5, (SHAFT_XY[1] + heap[1]) * 0.5 - 0.04), heap],
             width=0.085, seed=41 + i * 5)

    # The shaft: a black square opening. Nothing else on the roster is a pure
    # dark hole, so this is what says "mine" before any other detail resolves.
    part(bpy.ops.mesh.primitive_cube_add, shaft_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.030),
         scale=(0.28, 0.28, 0.03), size=1.0)

    # Winding gear: legs splay to the four corners of the shaft and the wheel
    # sits flat above it, so from overhead it is a ring inside a square with
    # four spokes running out to the corners.
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part(bpy.ops.mesh.primitive_cube_add, timber_mat,
             (SHAFT_XY[0] + dx * 0.14, SHAFT_XY[1] + dy * 0.14, 0.16),
             scale=(0.034, 0.034, 0.32), size=1.0)
    ring(timber_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.34), outer=0.19, thickness=0.034, height=0.05)
    for i in range(4):
        part(bpy.ops.mesh.primitive_cube_add, timber_mat, (SHAFT_XY[0], SHAFT_XY[1], 0.345),
             scale=(0.32, 0.021, 0.015), size=1.0, rotation=(0.0, 0.0, i * 0.7854))

    # Winding house: small hipped shed housing the engine.
    part(bpy.ops.mesh.primitive_cube_add, timber_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.08),
         scale=(0.30, 0.34, 0.14), size=1.0)
    hip_roof(timber_mat, (ENGINE_XY[0], ENGINE_XY[1], 0.15), width=0.28, depth=0.32,
             height=0.13, ridge_fraction=0.55)

    # Spoil heaps — ore-coloured cones. Their colour is the per-mine
    # differentiator across the extraction family (coal black here, rust for
    # iron, yellow for sulfur).
    for i, (hx, hy) in enumerate(HEAP_XY):
        part(bpy.ops.mesh.primitive_cone_add, ore_mat, (hx, hy, 0.06),
             radius1=0.15 - i * 0.02, radius2=0.0, depth=0.12)
