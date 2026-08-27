---
description: Take the next [gated] backlog item, implement it, gate it, and open a PR.
---

Take exactly ONE item and stop. This runs unattended, so the rules below are hard
constraints, not preferences.

## 1. Orient

- Read `vision.md` (§5's three checks), `backlog.md`, and `CLAUDE.md`.
- Run `gh pr list --state all --limit 10`. If an open PR already covers the item you
  were going to take, take the next one instead.
- `git fetch` does NOT advance the local branch pointer. Branch from `origin/master`
  explicitly, and confirm with `git log -1 --oneline origin/master`.

## 2. Choose

Take the **topmost unstarted `[gated]` item in `backlog.md`'s "Now" section.**

- **Never take a `[visual]` or `[design]` item.** `[visual]` needs a human or the
  playtest agent to look at a render; `[design]` needs the user. Taking one
  unattended produces work nobody can verify.
- Read the `decisions.md` entries the item cites before writing any code. They exist
  so settled questions are not re-derived.
- If the item fails any of `vision.md` §5's three checks, do not take it — say so and
  stop.
- If every "Now" item is `[visual]`/`[design]` or already has an open PR, stop and say
  the queue is empty. Do not invent work.

## 3. Implement

Branch: `<short-slug>-<YYYY-MM-DD>` off `origin/master`.

Follow `CLAUDE.md` — especially §1 (dependency injection via `@export NodePath`, no
cross-class `_private` access, signals over polling), §2 (comments are technical
detail only, quote the user verbatim for their decisions), and §3 (read terrain
through the sub-hex layer, never `HexCell` fields directly).

Two traps this codebase hits repeatedly:
- **Enumerate every caller** before wiring in a new rule. `HexPathfinder` has three
  neighbour-expansion loops and `HordeManager._replan_cheap()` goes through neither
  real search — it is the one that gets missed.
- **A new `class_name` file leaves `.godot/global_script_class_cache.cfg` stale.**
  Refresh with `--headless --editor --quit`, and re-run it if you created a second
  `class_name` file while the first refresh was running. Then
  `git checkout -- assets/` to drop the `.import` line-ending churn it causes.

## 4. Gate — all three must pass before committing

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

## 5. Land it

- Commit (message body explaining *why*, per the repo's existing style — read
  `git log` for the voice).
- Push, open a PR using `.github/pull_request_template.md`.
- Tick the item in `backlog.md` and append an entry to `devlog/2026-08.md`.
- If you settled a design question along the way, add it to `decisions.md`.
- Never grow `todo.md` back into a log.

Then stop. One item per run.
