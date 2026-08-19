"""assets/walls/gate_brick.png — Tier 1 gate: a brick gatehouse.

Brick piers with stone capstones over ironbound timber doors, matching
wall_brick.py's palette.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from models.walls.gate import build_gate  # noqa: E402

TIER = 1

PIER_COLOR = (0.55, 0.24, 0.17)
PIER_TRIM_COLOR = (0.46, 0.44, 0.40)
DOOR_COLOR = (0.44, 0.31, 0.19)
DOOR_DARK_COLOR = (0.35, 0.24, 0.15)
IRON_COLOR = (0.26, 0.25, 0.24)


def build():
    build_gate(TIER, PIER_COLOR, PIER_TRIM_COLOR, DOOR_COLOR, DOOR_DARK_COLOR, IRON_COLOR, plank_count=7)
