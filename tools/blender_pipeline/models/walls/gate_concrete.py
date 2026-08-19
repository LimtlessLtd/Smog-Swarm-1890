"""assets/walls/gate_concrete.png — Tier 2 gate: a concrete gatehouse.

Cast piers and riveted steel doors, matching wall_concrete.py's palette. The
"planks" here read as steel plating rather than boarding, which is why this
tier uses fewer, wider ones.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from models.walls.gate import build_gate  # noqa: E402

TIER = 2

PIER_COLOR = (0.58, 0.58, 0.60)
PIER_TRIM_COLOR = (0.67, 0.67, 0.68)
DOOR_COLOR = (0.46, 0.47, 0.50)
DOOR_DARK_COLOR = (0.37, 0.38, 0.41)
IRON_COLOR = (0.30, 0.29, 0.28)


def build():
    build_gate(TIER, PIER_COLOR, PIER_TRIM_COLOR, DOOR_COLOR, DOOR_DARK_COLOR, IRON_COLOR, plank_count=4)
