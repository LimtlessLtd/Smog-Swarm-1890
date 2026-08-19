"""assets/walls/gate_wooden.png — Tier 0 gate: a timber gatehouse.

Rough-hewn posts and boarded doors, matching wall_wooden.py's palette so a
gate set into a wooden palisade reads as part of the same fortification.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from models.walls.gate import build_gate  # noqa: E402

TIER = 0

PIER_COLOR = (0.36, 0.26, 0.16)
PIER_TRIM_COLOR = (0.30, 0.21, 0.13)
DOOR_COLOR = (0.47, 0.34, 0.21)
DOOR_DARK_COLOR = (0.38, 0.27, 0.17)
IRON_COLOR = (0.24, 0.23, 0.22)


def build():
    build_gate(TIER, PIER_COLOR, PIER_TRIM_COLOR, DOOR_COLOR, DOOR_DARK_COLOR, IRON_COLOR, plank_count=6)
