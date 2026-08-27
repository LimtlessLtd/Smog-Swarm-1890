# Project Rules

Godot 4.x / GDScript RTS. These rules override default behavior and apply to all code and comments written or edited in this repo.

## 0. Where things live (read order)

Restructured 2026-08-27; `todo.md` is no longer the spec-and-log dumping ground.

1. **`vision.md`** — what the game is for. Its section 5 has three checks every
   backlog item must pass. Read first.
2. **`backlog.md`** — what to build next. Items are tagged `[gated]` (a script can
   verify it), `[visual]` (needs a render or playtest agent), or `[design]` (needs the
   user), and split Now / Next / Deferred. **Only `[gated]` items may be taken by an
   unattended loop.**
3. **`decisions.md`** — settled calls and their reasons. **Read the relevant entry
   before re-opening any design question**; it exists so decisions are not re-derived.
4. **`design_doc.md`** — the numbers spec. Authoritative for terrain, economy,
   buildings, units, infestation (2.1), logistics (2.2), and vision/sound/light (6).
5. **`todo.md`** — index plus the reference sections that do not churn.
6. **`devlog/`** — append-only history of completed work. **Not read at session start.**

When work lands, update `backlog.md` (tick or remove the item) and append to
`devlog/`. When a design question gets settled, add it to `decisions.md`. Never grow
`todo.md` back into a log.

## 0.1 The gate

Three commands. All must pass before a commit lands.

```
python3 tools/ci/check_gdscript.py                     # brackets, indent, dup class_name, dead scene paths
python3 tools/ci/run_verifications.py                  # every scripts/test/verify_*.gd, exit 0 only if all pass
<godot> --headless scenes/main/Main.tscn --quit        # managers actually boot
```

The third is not optional and not the same as `--headless --quit`, which only checks
script parse validity and cannot catch a broken manager `_ready()`.

`run_verifications.py --list` shows what runs; pass substrings to filter. A timeout
counts as a failure on purpose — `verify_gates.gd` once hung for three hours.

**Visual work is not gated by any of these.** Run
`<godot> res://scenes/test/smoke_screenshot.tscn` (windowed, NOT headless — a headless
viewport has no texture to read) to confirm the game still renders at four framings.
Every real visual defect in this project was found by looking at an image, never by
reasoning about the code.

`/next-item` is the unattended loop's entry point and enforces all of the above.

## 1. Loose coupling / OOP

- Every new or edited manager/controller must follow Single Responsibility: one class, one reason to change. Don't add a new responsibility to an existing class just because it already has a `NodePath` to the thing you need — extract a collaborator instead.
- Dependency injection via `@export var x_path: NodePath` + a typed private `_x` var resolved in `_ready()` is the project's established DI convention. Keep using it. Never reach a dependency via `get_node("/root/...")` unless it's one of the five real global autoloads (`TickManager`, `TimeCycleManager`, `DisplaySettings`, `GameLaunchState`, `BackgroundExecutionManager`).
- Never read or write another class's underscore-prefixed (`_foo`) field from outside that class. Cross-class communication goes through public methods and signals only.
- Prefer signals (push) over polling another manager's public getters every frame/redraw (pull). A class that needs to react to another class's state change should connect to that class's signal, not re-derive the state itself.
- Before adding a new `@export var *_path: NodePath` to an already-wide class (roughly 8+ existing dependencies), extract a narrower collaborator that owns just the new dependency instead.
- No circular manager-to-manager references. If two managers both seem to need each other, one of them owns the data and the other listens to its signal.

## 2. Comments

- Comments contain technical detail and concrete specifics only: what the code does, why a non-obvious choice was made, what invariant/precondition/edge case matters. No narrative, no scene-setting, no restating what the code already says in prose form.
- When a comment explains a decision the user made, quote the user directly and verbatim (in quotation marks) instead of paraphrasing or dramatizing it.
- No filler qualifiers ("real bug found and fixed", "adversarial review", "genuinely", "deliberately" used as flavor rather than to mark an actual design tradeoff). State the fact plainly.

## 3. Terrain/passability granularity

- The Real-Geography Vector Terrain epic and the Sub-Hex Mechanical Layer epic exist specifically to move terrain and passability data off a single value per macro-hex. Before any new feature reads biome, terrain feature, elevation, or passability for a gameplay decision or a visual, check whether `SubHexTerrainQuery` / `SubHexPortalGraph` / `SubHexTerrainOverride` already answers that question at sub-hex (30m) resolution. If it does, read through that layer — never through `HexCell.biome_type` / `.terrain_feature` / `.elevation` / `.is_passable()` directly.
- Named exception, so it isn't relitigated every time: the STRATEGIC macro-routing graph (`HexPathfinder`, `HordeFlowField`, and the top level `SubHexPortalGraph` itself refines under) is hex-granularity BY DESIGN — one node per macro-hex is the abstraction the whole hierarchical pathfind is built on. Don't "fix" that into sub-hex; the sub-hex layer's job is refining WHERE within/between hexes a mover crosses, not deciding WHETHER two hexes are connected. `SubHexPortalGraph.find_portals()` returning empty still falls back to the hex center rather than blocking the macro edge — that's a known, documented gap (see the portal-offset function's own comment), not something to silently "fix" as a side effect of an unrelated task.
- A feature that flattens sub-hex data down to one value per hex to answer its own question — a majority vote, "does any part of this hex...", reusing `HexCell.is_passable()` for a new rendering/hazard/placement check — is the anti-pattern this rule exists to catch, even where the flattening looks reasonable in isolation. The worked example is `ElevationReliefView`: its first version drew a per-band tint, hex-edge contours and impassable hatching per whole hex off `HexCell`, and was rewritten to a slope-derived hillshade built per raster pixel (`ReliefImageBuilder`). Read that pair before adding a new terrain visual.
- One deliberate exception inside the sub-hex layer, so it isn't "corrected" later: the MOUNTAIN clause of passability is decided per macro hex (`SubHexPortalGraph._is_mountain_blocked()`), because `MountainPassCarver` opens passes by lowering `HexCell.elevation` at generation and that carve exists nowhere in the baked elevation raster. Deriving mountains per sub-cell from the raster re-seals every carved pass. `scripts/test/verify_boundary_blocking.gd` locks this down.
- If bringing a specific feature in line with this is out of scope for the current task, say so explicitly rather than silently building on the coarse field — a coarse implementation is easy to mistake for a complete one.
- Sub-hex sampling is not free: `SubHexTerrainQuery` caches per 30 m sub-cell in an unbounded static Dictionary, so anything that fans out across whole hex edges or areas can strand millions of entries. Measure before wiring such a check into a hot loop (`scripts/test/bench_portal_blocking.gd` is the template — the first cut of `is_boundary_impassable()` cost 2.18 ms/edge and ~178 cache entries/edge; an early-out rewrite took it to 0.02 ms and ~1).
