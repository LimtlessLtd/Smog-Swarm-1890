"""Shared gate geometry for the three tier gate assets.

"There should be a seperate gate asset and it needs to be 3 wall segments
long and it should look like a gate while also matching the general theme and
thickness of its wall equivalent, but it shouldnt be repeatable/stretch like
walls, you place 1 gate at a time" (user spec).

Every gate is the same arrangement seen from directly above — two piers at
the ends with a pair of doors meeting in the middle — differing only in
materials and in the ironwork each tier's doors carry. Building that once
here and letting each tier supply colours is what keeps the three reading as
the same STRUCTURE at three levels of construction, rather than as three
unrelated assets that happen to sit in a wall.

Two constraints the shape has to satisfy, both mechanical rather than
aesthetic:

  - The doors are the same depth as their own tier's wall band
    (strip.band_half_depth), so a gate set into a run of wall is exactly as
    thick as the wall it interrupts. The piers are allowed to be wider — a gatehouse should read
    as heavier than the wall — but not so wide that the frame clips them.
  - The ends are FLUSH with the frame, unlike a wall's overrun: a gate is
    placed once at a known length, so its texture is stretched onto exactly
    that length and anything past the frame would simply be cut off.
"""

import bpy

from render_common import flat_material, part
from models.walls.strip import GATE_SPAN_X, TILE_PERIOD, band_half_depth

# A gate matches the thickness of the wall tier it belongs to, so it takes
# that tier's own band depth rather than a shared one.
WALL_HALF_DEPTH_BY_TIER = tuple(band_half_depth(t) for t in range(3))
PIER_DEPTH_MULTIPLIER = 1.2  # A gatehouse reads as heavier than the wall — but the frame still has to contain it.
PIER_WIDTH = TILE_PERIOD * 0.36
PIER_HEIGHT = 0.72

DOOR_HEIGHT = 0.5
# Doors span whatever the piers leave between them; each leaf is half of it.
DOORWAY_HALF_WIDTH = GATE_SPAN_X / 2.0 - PIER_WIDTH
LEAF_WIDTH = DOORWAY_HALF_WIDTH


def build_gate(tier: int, pier_color, pier_trim_color, door_color, door_dark_color, iron_color, plank_count: int = 6):
    """`tier` selects the wall thickness this gate has to match (0 Wooden,
    1 Brick, 2 Concrete). `plank_count` is per LEAF — the boarding a top-down camera reads the
    doors by, since the doors' own faces are edge-on and invisible from
    there."""
    door_half_depth = WALL_HALF_DEPTH_BY_TIER[tier]
    pier_half_depth = min(door_half_depth * PIER_DEPTH_MULTIPLIER, band_half_depth(2))

    pier_mat = flat_material("Pier", pier_color)
    pier_trim_mat = flat_material("PierTrim", pier_trim_color)
    door_mat = flat_material("Door", door_color)
    door_dark_mat = flat_material("DoorDark", door_dark_color)
    iron_mat = flat_material("Iron", iron_color)

    for side in (-1.0, 1.0):
        pier_x = side * (GATE_SPAN_X / 2.0 - PIER_WIDTH / 2.0)
        part(bpy.ops.mesh.primitive_cube_add, pier_mat, (pier_x, 0, PIER_HEIGHT / 2.0),
             scale=(PIER_WIDTH, pier_half_depth * 2.0, PIER_HEIGHT), size=1.0)
        # Capstone, inset, so the pier reads as a built tower from overhead
        # rather than as a plain block of the same colour as the doors.
        part(bpy.ops.mesh.primitive_cube_add, pier_trim_mat, (pier_x, 0, PIER_HEIGHT + 0.03),
             scale=(PIER_WIDTH * 0.72, pier_half_depth * 1.5, 0.06), size=1.0)

        # One leaf per side, hinged at its pier and meeting its partner at
        # x = 0. Slightly lower than the piers so both are visible.
        leaf_x = side * (LEAF_WIDTH / 2.0)
        part(bpy.ops.mesh.primitive_cube_add, door_mat, (leaf_x, 0, DOOR_HEIGHT / 2.0),
             scale=(LEAF_WIDTH, door_half_depth * 2.0, DOOR_HEIGHT), size=1.0)

        for i in range(plank_count):
            # Boarding runs ACROSS the gate's length, i.e. the planks are
            # perpendicular to the direction of travel, which is what makes
            # the doors read as doors and not as more wall.
            plank_x = leaf_x + (float(i) / float(plank_count) - 0.5 + 0.5 / plank_count) * LEAF_WIDTH
            mat = door_dark_mat if i % 2 == 0 else door_mat
            part(bpy.ops.mesh.primitive_cube_add, mat, (plank_x, 0, DOOR_HEIGHT + 0.012),
                 scale=(LEAF_WIDTH / plank_count * 0.8, door_half_depth * 2.0, 0.024), size=1.0)

        # Cross-brace strapping at both ends of the leaf, and a ring handle
        # at the meeting edge — the ironwork that says "this opens".
        for band_x in (leaf_x - side * LEAF_WIDTH * 0.34, leaf_x + side * LEAF_WIDTH * 0.34):
            part(bpy.ops.mesh.primitive_cube_add, iron_mat, (band_x, 0, DOOR_HEIGHT + 0.03),
                 scale=(0.035, door_half_depth * 2.0, 0.02), size=1.0)
        part(bpy.ops.mesh.primitive_torus_add, iron_mat,
             (side * LEAF_WIDTH * 0.08, 0, DOOR_HEIGHT + 0.04),
             major_radius=0.05, minor_radius=0.014)

    # The seam where the two leaves meet, dead centre — the single most
    # legible "this is a gate" cue at map scale.
    part(bpy.ops.mesh.primitive_cube_add, iron_mat, (0, 0, DOOR_HEIGHT + 0.035),
         scale=(0.022, door_half_depth * 2.0, 0.03), size=1.0)
