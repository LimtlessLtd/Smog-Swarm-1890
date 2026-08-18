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
    parser.add_argument("--out", help="Output PNG path (not needed with --measure)")
    parser.add_argument("--resolution", type=int, default=2048)  # 4x the original 512 — user feedback ("all of them need to be at least 4 times bigger").
    parser.add_argument("--elevation", type=float, default=None, help="Override CATEGORY_ELEVATION_DEG for this run only")
    parser.add_argument("--fit", action="store_true",
                        help="Centre on the model and size the frame to it, instead of "
                             "add_camera()'s fixed ortho_scale")
    parser.add_argument("--ortho-scale", type=float, default=None,
                        help="With --fit: frame at this size rather than this model's own, "
                             "so a whole category keeps its relative sizes")
    parser.add_argument("--measure", action="store_true",
                        help="Print the model's fitted ortho_scale and exit without rendering")
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

    if args.measure:
        # Machine-readable and prefixed: Blender writes its own startup banner and
        # per-module noise to the same stdout, so render_category.py needs a line
        # it can match rather than "the last thing printed".
        print(f"ORTHO_SPAN {render_common.measure_content_span(args.category):.6f}")
        return
    if not args.out:
        raise SystemExit("--out is required unless --measure is given")

    # Absolute path, not args.out as-given: Blender's own scene.render.filepath
    # resolution for a relative path (no leading "//") does NOT reliably match
    # Python's os.getcwd() on Windows for an unsaved .blend — measured directly,
    # a relative "assets/walls/wall_brick.png" silently wrote to
    # "C:\assets\walls\wall_brick.png" instead of the launching shell's actual
    # working directory, no error either way (render_common.render_to()'s
    # bpy.ops.render.render(write_still=True) doesn't raise on this).
    out_path = os.path.abspath(args.out)
    out_dir = os.path.dirname(out_path)
    os.makedirs(out_dir, exist_ok=True)
    render_common.render_to(out_path, args.category, args.resolution,
                            fit=args.fit or args.ortho_scale is not None,
                            ortho_scale=args.ortho_scale)
    print(f"Rendered {out_path}")


if __name__ == "__main__":
    main()
