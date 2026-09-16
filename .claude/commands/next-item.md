---
description: Find the highest player-impact problem the unattended loop can act on, fix it, prove it (gate + playtest/render evidence), and open a PR.
---

Take exactly ONE problem and stop. This runs unattended, so the rules below are hard
constraints, not preferences. The goal is "improve the current player's experience",
not "implement the next missing feature" (`decisions.md` D94).

## 1. Orient

- Read `CLAUDE.md` (§0.2 is the selection model), `vision.md`, `PLAYER_EXPERIENCE.md`,
  `GAME_HEALTH.md`, then `backlog.md`.
- Run `gh pr list --state all --limit 10`. If an open PR already covers what you were
  going to take, take the next thing instead.
- `git fetch` does NOT advance the local branch pointer. Branch from `origin/master`
  explicitly, and confirm with `git log -1 --oneline origin/master`.

## 2. Look before choosing

Evidence first, so the choice is about the game rather than the list:

- Read `GAME_HEALTH.md`'s lowest states and their evidence.
- If a gameplay area is in question and no result from the current `origin/master`
  exists, run `python3 tools/playtest/run_scenarios.py <scenario>` for it (each takes
  minutes; do not run the whole set unless the choice needs it) and read the
  `concern` rows.
- For presentation, run `scenes/test/smoke_screenshot.tscn` windowed and look at the
  PNGs.

## 3. Choose

Pick the highest item in `CLAUDE.md` §0.2's priority order that is **actionable
unattended**:

- `[gated]` and `[visual-autonomous]` items are actionable. **Do not skip a
  `[visual-autonomous]` item because it is visual** (D95) — you have the tools to render
  and inspect it.
- `[visual-human]` and `[design]` are not. For a `[design]` item you may add a
  measurement or sharpen the question in `backlog.md` (numbered options, a
  recommendation with reasoning), but never decide it.
- `backlog.md`'s Now section is already sorted by the priority model. Prefer its
  topmost actionable item, unless your evidence from §2 shows a higher-priority problem
  that is not in the backlog — then add it (WHY / PLAYER EXPERIENCE / IMPLEMENTATION /
  VERIFICATION) and take it.
- The item must answer `CLAUDE.md` §0.2's five player-impact questions. If it cannot,
  it is not the highest-value thing; pick again.
- Performance, tooling and refactors rank 11 or lower. Take one only when everything
  above it is non-actionable, or when it blocks an item above it — and say which.
- Read the `decisions.md` entries the item cites before writing any code.
- If nothing actionable remains, stop and report the top three non-actionable items and
  what each needs from the user. Do not invent work.

## 4. Implement

Branch: `<short-slug>-<YYYY-MM-DD>` off `origin/master`.

Follow `CLAUDE.md` — especially §1 (dependency injection via `@export NodePath`, no
cross-class `_private` access, signals over polling), §2 (comments are technical
detail only, quote the user verbatim for their decisions), and §3 (read terrain
through the sub-hex layer, never `HexCell` fields directly).

Smallest complete change that meaningfully improves the experience. Do not rebuild
systems that exist.

Two traps this codebase hits repeatedly:
- **Enumerate every caller** before wiring in a new rule. `HexPathfinder` has three
  neighbour-expansion loops and `HordeManager._replan_cheap()` goes through neither
  real search — it is the one that gets missed.
- **A new `class_name` file leaves `.godot/global_script_class_cache.cfg` stale.**
  Refresh with `--headless --editor --quit`, and re-run it if you created a second
  `class_name` file while the first refresh was running. Then
  `git checkout -- assets/` to drop the `.import` line-ending churn it causes.

## 5. Prove it — code, then experience

**Gate — all three must pass before committing:**

```
python3 tools/ci/check_gdscript.py
python3 tools/ci/run_verifications.py
"E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe" --headless scenes/main/Main.tscn --quit
```

The third one matters: `--headless --quit` alone only checks script parse validity and
will not catch a broken manager `_ready()`.

**If the gate fails, fix it. If it fails twice on the same item, stop, leave the branch
unpushed, and report what failed.** Do not weaken a verification to make it pass, and
do not skip one because it looks unrelated.

**Experience evidence — required for anything a player would see or feel:**

- Gameplay change: run the relevant scenario before (on `origin/master`) and after, and
  put both check tables in the PR. A change that moves no measurement and shows nothing
  on screen has not been shown to improve anything — say so rather than claim it.
- `[visual-autonomous]` change: capture the render (`--shots`, `smoke_screenshot`, or a
  `preview_*` scene), **open the PNGs and look at them**, iterate until they show what
  was intended, and attach or describe them in the PR. No inspected image, not done.
- Ask plainly: did it create a decision, clarify feedback, or just add complexity?

## 6. Land it

- Commit (message body explaining *why*, per the repo's existing style — read
  `git log` for the voice).
- Push, open a PR using `.github/pull_request_template.md`, including the player-impact
  answers and the evidence from §5.
- Tick the item in `backlog.md` and append an entry to the current month's
  `devlog/YYYY-MM.md`.
- If an area's evidence changed, update its row in `GAME_HEALTH.md` — change a state
  only when the evidence supports it.
- If you settled a design question along the way, add it to `decisions.md`.
- Never grow `todo.md` back into a log.

Then stop. One problem per run.
