"""Re-render a whole asset category through render.py, framed to its content.

Run with SYSTEM python, not Blender's — this drives blender.exe once per
asset rather than running inside it:

    python tools/blender_pipeline/render_category.py --category icons --fit per-asset
    python tools/blender_pipeline/render_category.py --category buildings --fit shared

Exists because the two useful framings need different numbers of passes and
neither is a thing render.py can decide on its own:

  per-asset  One pass. Every asset is blown up to fill its own frame. Correct
             where relative size carries no meaning -- resource icons are UI
             glyphs in a fixed 20x20 slot (ResourceBarView.ICON_SIZE), and
             coal rendering 3x larger than cast_iron there was a defect, not
             a size relationship worth keeping.

  shared     Two passes: --measure every asset, then render them all at the
             largest span found. Every asset is re-CENTRED and the whole
             category grows by one common factor, so the sizes its authors
             built stay intact relative to each other. Correct for buildings,
             which TacticalHexView maps onto one fixed-size quad each
             (BUILDING_HALF_SIZE) -- a sprawling mechanised_farm reading as
             bigger than a watchtower is information, and per-asset framing
             would flatten every building to the same on-screen size.
"""

import argparse
import os
import re
import subprocess

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(os.path.dirname(_HERE))
_DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

# Model script stem -> asset key, for the assets whose in-game key was renamed
# after the model was written. BuildingVisuals._texture_key() is the authority
# on the right-hand side; a mismatch here doesn't error, it just writes a PNG
# no building ever loads and leaves the real one stale.
_OUTPUT_KEY_OVERRIDES = {
    "buildings": {
        "iron_foundry": "cast_iron_foundry",
        "gunpowder_mill": "saltpetre_powder_mill",
    },
}

_SPAN_RE = re.compile(r"^ORTHO_SPAN\s+([0-9.]+)\s*$", re.MULTILINE)


def _models(category: str) -> list[str]:
    directory = os.path.join(_HERE, "models", category)
    return sorted(
        os.path.join(directory, name)
        for name in os.listdir(directory)
        if name.endswith(".py") and not name.startswith("_")
    )


def _output_path(category: str, model_path: str) -> str:
    stem = os.path.splitext(os.path.basename(model_path))[0]
    key = _OUTPUT_KEY_OVERRIDES.get(category, {}).get(stem, stem)
    return os.path.join(_REPO, "assets", category, f"{key}.png")


def _run(blender: str, model: str, category: str, extra: list[str]) -> str:
    result = subprocess.run(
        [blender, "--background", "--python", os.path.join(_HERE, "render.py"), "--",
         "--model", model, "--category", category] + extra,
        capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"blender failed on {model}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def measure(blender: str, category: str, models: list[str]) -> dict[str, float]:
    spans = {}
    for i, model in enumerate(models, 1):
        # --measure builds the scene and does the projection maths but never
        # invokes Cycles, so this pass costs Blender startup rather than a render.
        match = _SPAN_RE.search(_run(blender, model, category, ["--measure"]))
        if match is None:
            raise SystemExit(f"no ORTHO_SPAN in --measure output for {model}")
        spans[model] = float(match.group(1))
        print(f"  [{i}/{len(models)}] {os.path.basename(model):48s} span {spans[model]:.4f}", flush=True)
    return spans


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--category", required=True)
    parser.add_argument("--fit", choices=("per-asset", "shared"), required=True)
    parser.add_argument("--resolution", type=int, default=2048)
    parser.add_argument("--blender", default=os.environ.get("BLENDER", _DEFAULT_BLENDER))
    parser.add_argument("--only", nargs="*", help="Model stems to limit this run to")
    args = parser.parse_args()

    models = _models(args.category)
    if args.only:
        wanted = set(args.only)
        models = [m for m in models if os.path.splitext(os.path.basename(m))[0] in wanted]
    if not models:
        raise SystemExit(f"no model scripts matched under models/{args.category}")

    extra = []
    if args.fit == "shared":
        print(f"Measuring {len(models)} {args.category} models...", flush=True)
        shared = max(measure(args.blender, args.category, models).values())
        print(f"Shared ortho_scale: {shared:.4f}", flush=True)
        extra = ["--ortho-scale", f"{shared:.6f}"]
    else:
        extra = ["--fit"]

    print(f"Rendering {len(models)} {args.category} models at {args.resolution}px...", flush=True)
    for i, model in enumerate(models, 1):
        out = _output_path(args.category, model)
        _run(args.blender, model, args.category,
             extra + ["--out", out, "--resolution", str(args.resolution)])
        print(f"  [{i}/{len(models)}] {os.path.basename(out)}", flush=True)


if __name__ == "__main__":
    main()
