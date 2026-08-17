"""CLI entry point for 8-directional renders (isometric 2.5D proof of concept /
future unit facing art). Run headless:

  blender --background --python tools/blender_pipeline/render_directional.py -- \
      --model tools/blender_pipeline/models/_test/facing_arrow.py --category units \
      --key facing_arrow --out-dir some/dir

Produces <out-dir>/<key>_n.png .. <key>_nw.png (see render_common.DIRECTIONS_8).
"""

import argparse
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import render_common  # noqa: E402


def _parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--category", required=True, choices=list(render_common.CATEGORY_ELEVATION_DEG.keys()))
    parser.add_argument("--key", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--resolution", type=int, default=512)
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

    os.makedirs(args.out_dir, exist_ok=True)
    render_common.render_directional_to(args.out_dir, args.key, args.category, args.resolution)
    print(f"Rendered {len(render_common.DIRECTIONS_8)} facings to {args.out_dir}/{args.key}_*.png")


if __name__ == "__main__":
    main()
