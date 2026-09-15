"""Verify that every unit/zombie facing PNG matches the compass name in its filename.

    python3 tools/ci/check_unit_facings.py

Exit 0 if every facing is right, 1 otherwise. Needs Pillow; it reads only the
shipped PNGs, so it does not need Blender or Godot.

WHY THIS EXISTS
---------------
The 8 facings are one model under an in-plane rotation, baked by yawing the
camera (render_common.render_directional_to). The sign of that yaw step is easy
to get wrong and nearly impossible to eyeball:

  * `n` and `s` are symmetric under the mirror the wrong sign produces, so half
    the roster looks correct either way.
  * `n` is yaw 0 under either sign, so it is byte-identical and never flags.
  * A contact sheet at thumbnail size reads as plausible in both directions.

On 2026-09-15 all three of those combined to produce a false alarm (a mirror was
reported that did not exist), then a real mirror (the "fix" was applied and
inverted 6 of 8 facings), then partial corruption when the bad render was
stopped mid-model and left `ne` wrong while the rest stayed right. None of it was
caught by looking; all of it was caught by this test.

THE TEST
--------
Facing i must equal the `n` frame rotated CLOCKWISE by 45*i on screen. Score
every candidate rotation by alpha-mask IoU and require the winner to be the
facing the filename claims.

Two things that look like reasonable implementations and are not:

  * Tracking a coloured landmark (a hat, a plume) instead of the whole mask. A
    colour tolerance wide enough to catch a hat also catches skin and gunstock,
    and the centroid then wanders between facings. Tried; produced garbage.
  * Cropping each facing to its own content box before comparing. A long model's
    box is tall-and-thin head-on and squarer at 45 degrees, so cropping puts
    cardinals and diagonals at different scales and falsely flags every diagonal.
    Unnecessary anyway: render_directional_to() renders all 8 at one shared
    ortho_scale aimed at the origin, so the raw frames are directly comparable.
"""

import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment without Pillow
    print("check_unit_facings: Pillow is not installed; skipping.")
    raise SystemExit(0)

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(os.path.dirname(_HERE))
ASSETS = os.path.join(_REPO, "assets")

DIRECTIONS_8 = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
SIZE = 160  # Mask resolution. Big enough to separate facings, small enough to stay quick.


def _mask(path):
    """Alpha mask of the RAW frame — deliberately not cropped. See module docstring."""
    image = Image.open(path).convert("RGBA")
    resized = image.resize((SIZE, SIZE), Image.LANCZOS)
    return resized.getchannel("A").point(lambda v: 255 if v > 110 else 0)


def _iou(a, b):
    pixels_a, pixels_b = a.load(), b.load()
    intersection = union = 0
    for y in range(SIZE):
        for x in range(SIZE):
            in_a, in_b = pixels_a[x, y] > 0, pixels_b[x, y] > 0
            if in_a or in_b:
                union += 1
                if in_a and in_b:
                    intersection += 1
    return intersection / union if union else 0.0


def _keys(category):
    directory = os.path.join(ASSETS, category)
    if not os.path.isdir(directory):
        return []
    found = set()
    for name in os.listdir(directory):
        if not name.endswith("_n.png"):
            continue
        stem = name[: -len("_n.png")]
        if all(os.path.exists(os.path.join(directory, "%s_%s.png" % (stem, d)))
               for d in DIRECTIONS_8):
            found.add(stem)
    return sorted(found)


def check(category, key):
    directory = os.path.join(ASSETS, category)
    north = _mask(os.path.join(directory, "%s_n.png" % key))
    rotations = [north.rotate(-45.0 * j, resample=Image.BICUBIC) for j in range(8)]
    wrong = []
    for i, facing in enumerate(DIRECTIONS_8):
        target = _mask(os.path.join(directory, "%s_%s.png" % (key, facing)))
        best = max(range(8), key=lambda j: _iou(rotations[j], target))
        if best != i:
            wrong.append("%s looks like %s" % (facing, DIRECTIONS_8[best]))
    return wrong


def main():
    total_wrong = 0
    checked = 0
    for category in ("units", "zombies"):
        for key in _keys(category):
            checked += 1
            wrong = check(category, key)
            total_wrong += len(wrong)
            status = "OK 8/8" if not wrong else "WRONG: " + ", ".join(wrong)
            print("%-9s %-30s %s" % (category, key, status))
    if checked == 0:
        print("check_unit_facings: no 8-facing sets found; nothing to check.")
        return 0
    print("\nChecked %d models, %d wrong facings." % (checked, total_wrong))
    return 1 if total_wrong else 0


if __name__ == "__main__":
    sys.exit(main())
