# Blender art pipeline

Every game asset (resource icon, unit, zombie, building, prop, wall,
terrain tile) is a real Blender scene built from primitives via `bpy`,
rendered headless to a transparent PNG. This is the user's own decision,
made explicit when asked to brainstorm an asset pipeline: **"lets use
blender only, no API AI Image gen needed"** — it replaces the AI-prompt
workflows previously documented in `assets/units/README.md`,
`assets/buildings/README.md`, and `assets/icons/README.md` (all now point
here; kept in place only as historical record of the prompts that were
never run, per those files' own updated status notes).

Requires Blender installed locally — this machine has
`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` (installed
via `winget install BlenderFoundation.Blender` this session). No API key,
no external service, no manual copy-pasting into a third-party tool —
Claude Code writes the model script, runs Blender headless, and the PNG
lands directly in `assets/`.

## Why this over the old AI-prompt pipeline

The AI-prompt pipeline (units/buildings/icons READMEs) was infrastructure
without an execution path — no image-generation tool exists in this
Claude Code environment, so every prompt sat unused waiting for a human to
paste it into an external tool. This pipeline closes that loop entirely:
Blender is a real local tool this environment can drive end-to-end, so
generation, rendering, and file placement all happen without a human
in the middle.

## How it works

- `render_common.py` — the shared rig every asset script uses. Owns scene
  reset, camera framing (per-category elevation angle — steep bird's-eye
  for most categories, shallower for icons and for anything with a body
  that a steep angle would foreshorten into nothing — see
  `CATEGORY_ELEVATION_DEG`'s own comment), the cheap 2-tone toon shader
  (`flat_material()` — a hardcoded shader-graph light direction, not real
  scene lighting, so it's deterministic and matches "flat painterly
  cel-shading" exactly rather than approximating it), the Freestyle black
  outline, and forces `view_transform = 'Standard'` (see "AgX gotcha" below).
  `part()`/`curved_part()`/`sash()`/`wheel()` are shared body-part helpers
  every unit/vehicle script builds on instead of repeating boilerplate.
- `render.py` — single-facing CLI: `blender --background --python render.py
  -- --model <path> --category <cat> --out <path.png>`.
- `render_directional.py` — 8-facing CLI (see "Directional facing" below):
  `blender --background --python render_directional.py -- --model <path>
  --category <cat> --key <name> --out-dir <dir>`, writes
  `<dir>/<key>_n.png` .. `<key>_nw.png` (`render_common.DIRECTIONS_8`).
- `models/<category>/<key>.py` — one file per asset, each exposing a
  `build()` function that adds mesh objects to the scene via the shared
  helpers above.

Every asset script writes its own model-specific rationale as comments —
why a particular silhouette element exists, what it's meant to
distinguish from — rather than repeating it here. Read the script itself.

## AgX gotcha (cost real time to find — don't reintroduce it)

Blender 4.0+/5.x defaults `view_transform` to `AgX`, a photographic
tone-mapping curve. It measurably desaturates/darkens rendered colors —
confirmed on a real render: `TRUNCHEON_COLOR = (0.72, 0.18, 0.12)` should
encode to `~(220, 117, 97)` in plain sRGB but came out `(172, 96, 77)`
under AgX, enough that a user reviewing the result reported "no red or
purple, just light blue." `render_common.setup_render()` forces `Standard`
— if a future edit to that function ever drops it, every role-accent color
across the whole roster silently mutes again.

## Directional facing (8-way)

`render_directional.py` sweeps the camera through `DIRECTIONS_8` yaw
angles around a model built once (not rebuilt per direction) — the
mechanism proven on a throwaway test shape (`models/_test/facing_arrow.py`)
before any real unit used it. Consumed on the Godot side by
`GameEnums.Facing8` / `FacingUtil.gd` / `UnitVisuals.unit_texture(type,
facing)` / `ZombieVisuals.zombie_texture(variant, facing)` /
`TacticalEntityLayer._advance_facing()` — see those files' own doc
comments for the GDScript half of this feature. Static categories
(buildings/props/walls/terrain/icons) never need this — only units and
zombies move.

## Role-accent color rule (unit/zombie-adjacent categories only)

Per `assets/units/README.md`'s original Style DNA, now enforced in code
via each unit script's own constants: **Melee = deep red, Ranged = deep
blue, Special = deep purple** — always vivid/saturated, always a real
surface with enough area to survive the Freestyle outline (see "Minimum
accent size" below), never a wash over the whole figure. Every unit script
carries this as its own `_COLOR` constant with a comment naming which role
it is. Zombies have no role system and use no accent color at all — see
`models/zombies/zombie_0.py`'s own doc comment.

## Minimum part thickness (found twice — armoured_command_car.py's antenna,
## then watchtower.py's whole leg/bracing structure)

A thin cylinder (radius ≈0.015-0.025 in local units) reads as almost
solid black — thinner than the Freestyle outline stroke itself, so
whatever color the fill is barely survives. This isn't only an
accent-color problem: watchtower.py's entire first-pass leg/bracing
structure (radius 0.025) rendered as a near-solid dark silhouette with no
readable structure at all, confirmed on a real render, not assumed. Rule
of thumb for THIS pipeline's usual scale (roughly unit-height humanoids,
building footprints ~0.5-1.5 units wide): **any structural cylinder/strut
needs radius ≥0.035-0.045**, not just accent-bearing ones. For
accent-bearing parts specifically, also make sure the color has a second,
bigger surface elsewhere on the model (a trim stripe, a sash, a big flat
weapon) so it reads even if one thin element's contribution is marginal.

Related: two colors close in *value* (lightness), not just different
hues, can blend into one silhouette even at full opacity — watchtower.py's
first-pass wood (0.34, 0.24, 0.15) and roof (0.22, 0.16, 0.12) colors were
close enough in darkness that the whole tower read as one undifferentiated
dark mass. Keep adjacent parts' colors far enough apart in lightness, not
just hue, to read as separate pieces.

## Producing a new asset

1. Write `models/<category>/<key>.py` with a `build()` function, following
   an existing script in the same category as a template (units in
   particular share a lot of proportions — legs/torso/belt/collar — copy
   from the nearest existing unit and change headwear/weapon/color).
2. Render one test facing first — `render.py`, not `render_directional.py`
   — and actually look at it (zoomed, not just the thumbnail) before
   committing to a full 8-direction batch.
3. For units/zombies, run `render_directional.py` into a scratch directory
   first, build a comparison grid, and verify the role color survives
   pixel-sampling AND a zoomed visual check — the AgX and thin-accent bugs
   above both looked fine in a compressed thumbnail and were wrong.
4. Once approved, render into the real `assets/<category>/` directory —
   `UnitVisuals`/`ZombieVisuals`/etc. all fall back cleanly to their old
   procedural shape for anything not yet authored, so partial coverage
   during development is fine.
