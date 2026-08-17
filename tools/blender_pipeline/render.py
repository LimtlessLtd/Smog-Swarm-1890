"""CLI entry point for the Blender art pipeline. Run headless:

  blender --background --python tools/blender_pipeline/render.py -- \
      --model tools/blender_pipeline/models/icons/coal.py --category icons \
      --out assets/icons/coal.png

Everything after the bare "--" is this script's own argv (Blender strips its
own args before that point) — see render_common.py's module docstring.

--model points at a python file that defines build() -> None; it's expected
to add mesh objects to the scene using render_common.flat_material() for
color. This runner loads that file, calls build(), then renders.
"""

import argparse
import importlib.util
import os
import sys

# Blender's bundled Python doesn't put this pipeline's own directory on
# sys.path automatically — needed so `import render_common` resolves.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import render_common  # noqa: E402


def _parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Path to a python file defining build()")
    parser.add_argument("--category", required=True, choices=list(render_common.CATEGORY_ELEVATION_DEG.keys()))
    parser.add_argument("--out", required=True, help="Output PNG path")
    parser.add_argument("--resolution", type=int, default=2048)  # 4x the original 512 — user feedback ("all of them need to be at least 4 times bigger").
    parser.add_argument("--elevation", type=float, default=None, help="Override CATEGORY_ELEVATION_DEG for this run only")
    return parser.parse_args(argv)


def _load_model_module(path: str):
    spec = importlib.util.spec_from_file_location("asset_model", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    args = _parse_args()
    render_common.reset_scene()

    model = _load_model_module(args.model)
    model.build()

    if args.elevation is not None:
        render_common.CATEGORY_ELEVATION_DEG[args.category] = args.elevation

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    render_common.render_to(args.out, args.category, args.resolution)
    print(f"Rendered {args.out}")


if __name__ == "__main__":
    main()
