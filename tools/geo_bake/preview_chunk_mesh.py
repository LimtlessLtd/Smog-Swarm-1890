"""Rasterises baked .tmesh chunks to a PNG so a bake change can be LOOKED at.

Every real defect in this epic so far was found by rendering the result, not
by reasoning about the numbers -- the doubled river width, the double-composited
relief tiles, the unreachable slope constant. The in-engine harnesses
(scripts/test/preview_*.gd) do that for the shipped view, but they need a Godot
boot, the streaming layer and a camera, which is far too slow a loop for
sweeping a bake constant across half a dozen values.

This draws the mesh directly from the file with flat per-class colour, which is
also the right picture for judging SHAPE: a texture hides the very thing being
compared. Panels are laid out left to right so several bakes of the same chunk
sit side by side under one look.

  python preview_chunk_mesh.py --chunk 21 25 --dirs a=../../assets/terrain_data/mesh b=out/smoothed
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_codec import encode_png_rgb8  # noqa: E402
from vector_mesh_format import chunk_filename, decode_chunk  # noqa: E402

## Flat, high-contrast, and deliberately NOT the shipped art's palette: the
## point is to see where one class stops and the next starts.
CLASS_COLOR = {
    0: (108, 118, 84),    # MOORLAND
    1: (168, 176, 104),   # FARMLAND
    2: (150, 142, 138),   # URBAN
    3: (112, 96, 96),     # INDUSTRIAL
    4: (104, 132, 116),   # WETLAND
    5: (62, 104, 156),    # WATERWAY
    6: (150, 146, 132),   # HIGHLAND
    7: (52, 92, 48),      # WOODLAND
    8: (140, 116, 72),    # HEATHLAND
}
BACKGROUND = (24, 24, 28)


## bake_vector_landcover.CHUNK_SIZE_WU. Every chunk covers exactly this, so it
## is the scale to draw at -- NOT the chunk's own vertex extent, which stops
## short wherever the outermost geometry does and would silently draw two
## chunks at two different scales.
CHUNK_SIZE_WU = 4096.0


def rasterise(path: str, size: int) -> np.ndarray:
    """One chunk -> (size, size, 3) uint8, y flipped so north is up.

    Barycentric fill over each triangle's own pixel bounding box. A scanline
    converter would be faster, but a chunk is ~33k small triangles and the
    bounding boxes are correspondingly tiny, so the whole thing is well under a
    second and the simple version cannot get the edge cases wrong.
    """
    mesh = decode_chunk(open(path, "rb").read())
    verts = np.asarray(mesh["verts"], dtype=np.float64) * mesh["quant"]
    tris = np.asarray(mesh["tris"], dtype=np.int64)
    classes = np.asarray(mesh["tri_classes"], dtype=np.int64)

    px = verts * (size / CHUNK_SIZE_WU)

    image = np.zeros((size, size, 3), dtype=np.uint8)
    image[:] = BACKGROUND
    ys, xs = np.mgrid[0:size, 0:size]

    for tri, code in zip(tris, classes):
        a, b, c = px[tri[0]], px[tri[1]], px[tri[2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))) + 1, size)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))) + 1, size)
        if x0 >= x1 or y0 >= y1:
            continue
        sub_x = xs[y0:y1, x0:x1] + 0.5
        sub_y = ys[y0:y1, x0:x1] + 0.5
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if d == 0.0:
            continue
        w0 = ((b[1] - c[1]) * (sub_x - c[0]) + (c[0] - b[0]) * (sub_y - c[1])) / d
        w1 = ((c[1] - a[1]) * (sub_x - c[0]) + (a[0] - c[0]) * (sub_y - c[1])) / d
        inside = (w0 >= 0.0) & (w1 >= 0.0) & (w0 + w1 <= 1.0)
        if not inside.any():
            continue
        image[y0:y1, x0:x1][inside] = CLASS_COLOR.get(int(code), (255, 0, 255))

    return image[::-1]


CLASS_NAME = {
    0: "MOORLAND", 1: "FARMLAND", 2: "URBAN", 3: "INDUSTRIAL", 4: "WETLAND",
    5: "WATERWAY", 6: "HIGHLAND", 7: "WOODLAND", 8: "HEATHLAND",
}


def stats(path: str) -> dict:
    """Triangle/vertex counts and per-class share of chunk AREA.

    Area share, not triangle share: a conditioning pass that welds a mosaic
    changes triangle counts by much more than it changes coverage, so counting
    triangles would report a class as decimated when only its triangulation
    got simpler. The two together are what says whether a bake change moved
    the map or only its mesh.
    """
    mesh = decode_chunk(open(path, "rb").read())
    verts = np.asarray(mesh["verts"], dtype=np.float64) * mesh["quant"]
    tris = np.asarray(mesh["tris"], dtype=np.int64)
    codes = np.asarray(mesh["tri_classes"], dtype=np.int64)
    e1 = verts[tris[:, 1]] - verts[tris[:, 0]]
    e2 = verts[tris[:, 2]] - verts[tris[:, 0]]
    area = np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) * 0.5
    total = area.sum()
    return {
        "tris": len(tris), "verts": len(verts), "bytes": os.path.getsize(path),
        "share": {c: area[codes == c].sum() / total * 100.0 for c in CLASS_NAME},
    }


def print_stats(named: list) -> None:
    print(f"\n{'':12s}" + "".join(f"{n:>14s}" for n, _ in named))
    print(f"{'triangles':12s}" + "".join(f"{s['tris']:>14,}" for _, s in named))
    print(f"{'vertices':12s}" + "".join(f"{s['verts']:>14,}" for _, s in named))
    print(f"{'KB':12s}" + "".join(f"{s['bytes']/1024:>14,.0f}" for _, s in named))
    for code, name in CLASS_NAME.items():
        shares = [s["share"][code] for _, s in named]
        if max(shares) < 0.05:
            continue
        print(f"{name:12s}" + "".join(f"{v:>13.2f}%" for v in shares))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--chunk", type=int, nargs=2, required=True, metavar=("X", "Y"))
    ap.add_argument("--dirs", nargs="+", required=True,
                    help="one or more mesh directories, drawn left to right")
    ap.add_argument("--size", type=int, default=900, help="pixels per panel")
    ap.add_argument("--block", type=int, nargs=2, metavar=("W", "H"),
                    help="draw a WxH grid of chunks butted together with no gap, from the FIRST "
                         "--dir, with --chunk as the bottom-left corner. The only way to see a "
                         "chunk SEAM: each chunk is baked from geometry already clipped to its "
                         "own box, so classes can disagree across the join, and a gap between "
                         "panels would hide exactly that")
    ap.add_argument("--out", default="chunk_preview.png")
    args = ap.parse_args()

    if args.block:
        wide, high = args.block
        rows = []
        for y in range(args.chunk[1] + high - 1, args.chunk[1] - 1, -1):  # north at the top
            row = []
            for x in range(args.chunk[0], args.chunk[0] + wide):
                path = os.path.join(args.dirs[0], chunk_filename(x, y))
                row.append(rasterise(path, args.size) if os.path.exists(path)
                           else np.full((args.size, args.size, 3), BACKGROUND, dtype=np.uint8))
            rows.append(np.concatenate(row, axis=1))
        joined = np.concatenate(rows, axis=0)
        h, w = joined.shape[:2]
        with open(args.out, "wb") as f:
            f.write(encode_png_rgb8(w, h, joined.tobytes()))
        print(f"wrote {args.out} ({w}x{h}), {wide}x{high} chunks from {args.dirs[0]}")
        return

    panels = []
    measured = []
    for d in args.dirs:
        path = os.path.join(d, chunk_filename(args.chunk[0], args.chunk[1]))
        if not os.path.exists(path):
            print(f"  MISSING {path}")
            continue
        panels.append(rasterise(path, args.size))
        measured.append((os.path.basename(d.rstrip("/\\")) or d, stats(path)))
        print(f"  drew {path}")
    if not panels:
        raise SystemExit("no panels drawn")
    print_stats(measured)

    gap = np.zeros((args.size, 6, 3), dtype=np.uint8)
    joined = panels[0]
    for p in panels[1:]:
        joined = np.concatenate([joined, gap, p], axis=1)

    h, w = joined.shape[:2]
    with open(args.out, "wb") as f:
        f.write(encode_png_rgb8(w, h, joined.tobytes()))
    print(f"wrote {args.out} ({w}x{h})")


if __name__ == "__main__":
    main()
