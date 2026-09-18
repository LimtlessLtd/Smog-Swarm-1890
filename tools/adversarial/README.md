# Automated Claude + Codex development

This runner lets Claude implement one bounded gameplay task and asks Codex to
independently challenge the result. It uses the existing project rules in
`CLAUDE.md`, runs the three required code gates, and requires task-specific
gameplay or visual evidence before accepting a change.

Claude is used for task selection and implementation so the heavier workload
uses the Claude subscription. Codex is a fresh, read-only critic for every
attempt. Neither agent can make a passing result by merely claiming the work is
complete.

## Scheduled automation

**Autonomous adversarial development** is active in Codex Desktop and runs every
five hours while the PC and the Codex Desktop automation service are available.
It invokes:

```powershell
python tools/adversarial/run.py auto --publish-pr
```

The scheduler is intentionally quiet when there is no eligible task or an
unchanged non-actionable state. It reports a passed change, a blocker, an
authentication failure, a baseline failure, or a repeated problem that needs
your attention. It cannot start a second run while a prior run holds the local
runner lock.

## What an automatic run does

1. Creates or resumes the local `codex/adversarial-autopilot` branch in the
   sibling worktree `E:\Source\SMOG-SWARM-1890-adversarial-autopilot`.
2. Runs the Godot import and the project's required baseline checks before any
   model receives an implementation task.
3. Uses a read-only Claude pass to select one eligible, bounded backlog task.
   Design decisions and work requiring human visual or taste judgment are not
   eligible.
4. Gives the selected task to Claude in the isolated worktree. Claude may edit
   source and run a narrowly allowed set of local checks, but cannot commit,
   push, merge, rebase, open a pull request, or modify the main checkout.
5. Re-runs import plus `check_gdscript.py`, `run_verifications.py`, and a
   headless boot of `scenes/main/Main.tscn`.
6. Gives Codex the task, actual diff, builder summary, and gate logs in a
   read-only sandbox. Codex must return schema-validated findings with evidence.
7. Returns findings to Claude for up to three rounds. It accepts only zero
   findings, complete required evidence, and passing gates.
8. On success, creates one commit on the autopilot branch, pushes it, and creates
   or updates a GitHub pull request targeting `master`. It never merges, fetches,
   rebases, or touches the primary checkout.

If a run fails or needs human input, later scheduled runs pause until it has
been inspected and explicitly resolved. The worktree and report remain in place
so the evidence is available.

## Your current worktree

Your primary checkout currently contains uncommitted work. Automatic runs do
not include, modify, stash, or commit it. The first automatic run starts from
the committed base supplied by `--base` (default `HEAD`); later runs continue
only from the dedicated autopilot branch. That prevents the scheduled process
from silently developing against a partial version of your work.

Each accepted autonomous change is published to the dedicated autopilot pull
request. Review and merge that pull request yourself. The runner never merges it
or changes your primary checkout.

## Check status and run manually

Run these commands in `E:\Source\SMOG-SWARM-1890`:

```powershell
python tools/adversarial/run.py doctor
python tools/adversarial/run.py auto --dry-run
```

`doctor` verifies the locally installed native executables and authentication
without exposing credentials. `auto --dry-run` resolves the intended base and
prints the intended roles and gates without creating a worktree or contacting a
model.

For a focused task that should not become a local autopilot commit:

```powershell
New-Item -ItemType Directory -Force .adversarial | Out-Null
Copy-Item tools/adversarial/task-template.md .adversarial/task.md
# Edit .adversarial/task.md, then:
python tools/adversarial/run.py run --task-file .adversarial/task.md --dry-run
python tools/adversarial/run.py run --task-file .adversarial/task.md
```

Manual runs use an isolated temporary worktree, require the same adversarial
review, and deliberately leave accepted changes uncommitted for your review.

Useful controls:

```powershell
# Use a specific initial commit or branch, then retain at most two repair rounds.
python tools/adversarial/run.py auto --publish-pr --base master --max-rounds 2

# Acknowledge that an inspected failed run should no longer block the scheduler.
python tools/adversarial/run.py resolve --run-id YYYYMMDD-HHMMSS-XXXXXXXX
```

Resolve does not repair code, clean a worktree, or accept a change. It only
acknowledges an inspected non-running report. The autopilot worktree must still
be clean before the next automatic run.

## Evidence and limits

The three project gates demonstrate that the code runs. They do not prove that
gameplay is fun or a visual change looks right. The runner requires the
before/after scenario evidence for gameplay work and inspected captures for
visual work that `CLAUDE.md` already requires. It stops when the necessary
evidence cannot be generated autonomously or when a user design choice is
needed.

All transcripts, prompts, logs, reports, and task snapshots are local under
`.adversarial/runs/`, which is ignored by Git and may contain source code and
task details. The runner has a per-command timeout and a total-run limit shorter
than the five-hour schedule; failures are retained rather than retried in a
tight loop.

Claude tool restrictions and Codex's read-only sandbox constrain the agents,
but this is not an operating-system sandbox. Keep the project and its local
automation environment trusted. Usage remains subject to both accounts' current
availability and limits.

If either CLI needs a new interactive sign-in:

```powershell
codex login
claude auth login --claudeai
```

## Verify the runner itself

```powershell
python -m unittest discover -s tools/adversarial -p test_run.py -v
```

The tests simulate model and check output; they do not spend model usage or
develop a game feature.

## References

- [Codex non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Codex authentication](https://learn.chatgpt.com/docs/auth)
- [Claude Code programmatic usage](https://code.claude.com/docs/en/headless)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference)
- [Claude structured-output handling](https://code.claude.com/docs/en/agent-sdk/structured-outputs)
