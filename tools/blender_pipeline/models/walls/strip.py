"""Shared geometry contract for the wall and gate strip assets.

A wall texture is tiled along a Line2D by WallVisuals; a gate is stretched
once onto a fixed-length one. Both are rendered by
render_common.render_strip_to() into a frame of exactly (span_x, span_y)
world units.

THE FRAME'S ASPECT IS THE CONTRACT, and it is not free. Line2D maps a
texture's width along the line at a fixed pixels-to-units rate and its full
height across the line's width, so the shape the art is authored at is the
shape it is drawn at only if the game uses the matching numbers. Those live
in WallVisuals:

    one texture repeat  = WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS   (span_x)
    drawn wall width    = that, times STRIP_HEIGHT / TILE_PERIOD       (span_y)

So a full-length wall piece shows exactly one repeat, adjacent pieces line
their patterns up, and nothing is stretched. Changing STRIP_HEIGHT here
without changing WallVisuals.STRIP_ASPECT_RATIO squashes every wall in the
game; they are two halves of one number.

  TILE_PERIOD    one repeat of a wall, and one wall segment's worth of a gate
  STRIP_HEIGHT   the frame's height
  BAND_DEPTH_BY_TIER  how much of that height each tier's wall actually fills

Tier thickness is authored in the ART rather than by drawing a wider line
per tier: the line's width is what the texture's height maps onto, so a
per-tier line width would stretch a fixed-height texture by a different
amount per tier. Making concrete look heavier than timber is the model's
job, not the renderer's.

Not a Blender module: it imports nothing from bpy and only computes numbers
and positions, so the wall/gate scripts and the verifier can all read it.
"""

TILE_PERIOD = 1.0

# Half as tall as one repeat is long. A wall piece is 100 m of real frontage
# (WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS) so this draws it about 50 m
# wide — heavily exaggerated, like every other structure in this game's
# Tactical view, and chosen to read as a solid barrier at the zoom the
# player actually fights at rather than to be true to scale, at which a real
# wall would be a sub-pixel hairline.
STRIP_HEIGHT = TILE_PERIOD * 0.5

# Per WallCatalog tier: 0 Wooden, 1 Brick, 2 Concrete. Rising fractions of
# the frame, so each tier visibly reads as sturdier than the last before the
# player checks its HP. The remainder is margin for the Freestyle outline,
# which is stroked centred on the silhouette and would be shaved off where
# the wall meets the frame edge — the same reason
# render_common.CONTENT_MARGIN_FRACTION exists for fitted renders.
BAND_DEPTH_BY_TIER = (0.68, 0.76, 0.84)

# A gate is "3 wall segments long" (user spec) and is placed one at a time
# rather than tiled, so its frame is this many periods wide at the same
# height — which is what makes it come out the same thickness as the wall
# it interrupts.
GATE_SEGMENTS = 3
GATE_SPAN_X = TILE_PERIOD * GATE_SEGMENTS

# How far past the frame a TILED asset's geometry runs, so the frame edges
# cut through solid geometry instead of the wall stopping short of them.
# Ending short is what leaves a gap between repeats. Gates do not overrun —
# their ends are the ends of the asset.
OVERRUN = TILE_PERIOD * 1.5


def band_half_depth(tier: int) -> float:
    return STRIP_HEIGHT * BAND_DEPTH_BY_TIER[tier] / 2.0


def periodic_positions(spacing: float, phase: float = 0.0) -> list:
    """X positions of a feature repeating every `spacing`, covering the whole
    overrun.

    Anchored to multiples of `spacing` measured from the ORIGIN rather than
    from the left end, which is what makes the pattern identical at x and at
    x + TILE_PERIOD. Laying features out from the left end instead puts the
    phase at the mercy of where the run happens to start, and the seam then
    depends on whether OVERRUN divides `spacing` — a bug that only shows up
    once two copies are placed side by side in game.
    """
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    steps = int(OVERRUN / spacing) + 1
    return [(i * spacing) + phase for i in range(-steps, steps + 1)]
