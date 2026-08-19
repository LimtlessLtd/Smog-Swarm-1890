"""Bakes one hex's relief at several --slope-full values and writes them side
by side, so the constant can be chosen by looking rather than by argument.

    python compare_relief_slope.py --q 82 --r 118

_SLOPE_METRES_AT_FULL sets how much rise across one 30 m pixel counts as a
full-strength slope, so it decides how much of the shading range ORDINARY
ground gets. Too high and every real British hillside lands in the bottom few
percent and the map reads flat -- which is what the first bake did at 12.0 m
(a 40% grade, steeper than almost anything in the corridor). Too low and
everything saturates into a hard black-and-white relief with no gradation.

Output is a single PNG strip, each panel labelled by a tick mark count down its
left edge (one per panel index) since there is no font here -- panels are in the
order given on the command line and printed to stdout alongside.

Composited over mid-grey rather than saved with alpha: these bytes are an
overlay, and judging them on white makes every value look far too weak.
"""

import argparse
import os
import shutil
import subprocess
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from png_codec import encode_png_rgb8  # noqa: E402
from bake_fine_tiles import FINE_TILE_PIXELS  # noqa: E402

_DEFAULT_SLOPES = [2.0, 3.5, 5.0, 8.0, 12.0]
_GAP_PX = 6


def read_gray(path: str) -> np.ndarray:
    """Minimal 8-bit greyscale PNG reader for filter types 0 and 1.

    png_codec.decode_png_rgb8() is truecolour-only by design, and this is the
    only place that needs to read back what encode_png_gray8() wrote.
    """
    data = open(path, "rb").read()
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"IDAT":
            idat += chunk
        pos += 12 + length
    width, height = ihdr[0], ihdr[1]
    raw = zlib.decompress(idat)
    out = np.zeros((height, width), dtype=np.uint8)
    index = 0
    for y in range(height):
        filter_type = raw[index]
        index += 1
        previous = 0
        for x in range(width):
            value = raw[index]
            index += 1
            if filter_type == 1:
                value = (value + previous) & 0xFF
            out[y, x] = value
            previous = value
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--q", type=int, default=82)
    parser.add_argument("--r", type=int, default=118)
    parser.add_argument("--slopes", type=float, nargs="+", default=_DEFAULT_SLOPES)
    parser.add_argument("--out", type=str, default="relief_slope_comparison.png")
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    panels = []
    for slope in args.slopes:
        out_dir = os.path.join(here, "cache", f"slope_{slope:g}")
        shutil.rmtree(out_dir, ignore_errors=True)
        subprocess.run(
            [sys.executable, os.path.join(here, "bake_fine_relief.py"),
             "--center-q", str(args.q), "--center-r", str(args.r), "--radius", "0",
             "--slope-full", str(slope), "--out-dir", out_dir, "--force"],
            cwd=here, check=True, stdout=subprocess.DEVNULL,
        )
        tile = read_gray(os.path.join(out_dir, f"{args.q}_{args.r}.png"))
        contrast = int(tile.max()) - int(tile.min())
        # Standard deviation, not just min/max: one cliff pixel can stretch the
        # range while the ground the player actually looks at stays flat, so the
        # spread is the number that tracks "does this read as terrain".
        print(f"slope_full={slope:5.1f}  min={tile.min():3d} max={tile.max():3d} "
              f"range={contrast:3d}  std={tile.std():5.1f}")
        panels.append(tile)

    height = FINE_TILE_PIXELS
    width = len(panels) * FINE_TILE_PIXELS + (len(panels) - 1) * _GAP_PX
    canvas = np.zeros((height, width), dtype=np.uint8)
    for i, panel in enumerate(panels):
        x = i * (FINE_TILE_PIXELS + _GAP_PX)
        canvas[:, x:x + FINE_TILE_PIXELS] = panel
        # Tick marks: i+1 short bars down the panel's left edge, so a panel can
        # be identified in the image without any text rendering.
        for tick in range(i + 1):
            top = 6 + tick * 10
            canvas[top:top + 6, x + 4:x + 10] = 255

    rgb = np.stack([canvas] * 3, axis=-1)
    open(os.path.join(here, args.out), "wb").write(encode_png_rgb8(width, height, rgb.tobytes()))
    print(f"\npanels left to right (ticks = index): {', '.join(f'{s:g}' for s in args.slopes)}")
    print(f"wrote {os.path.join(here, args.out)}")


if __name__ == "__main__":
    main()
