#!/usr/bin/env python3
"""Run every scripts/test/verify_*.gd and report pass/fail as one gate.

The scripts already existed and already agreed on a convention; nothing aggregated
them, so "did I break something" had no single answer. This is that answer.

Three classes, all detected from the file rather than configured:
  * `extends SceneTree`          -> `--headless -s scripts/test/X.gd`
  * `extends Node`               -> `--headless scenes/test/X.tscn`
  * header says "NOT --headless" -> WINDOWED: skipped by default, run with --windowed

The `-s` split matters: script mode cannot resolve autoload identifiers, which is why
the scene-based half exists (see verify_gates.gd, whose three-hour hang was
misdiagnosed as a gate bug before it moved to a .tscn).

The windowed split matters just as much. verify_save_screenshot.gd has to rasterise,
and a headless viewport has no texture to read -- run headless it does not fail, it
HANGS. That is how this runner's own timeout bug was found.

Exit code is 0 only if every verification that ran passed. A timeout counts as a
failure: an unattended loop must not inherit a hang.

Usage:
  python3 tools/ci/run_verifications.py [--list] [--windowed] [--all]
                                        [--timeout N] [--godot PATH] [FILTER...]

  FILTER      substring match on verification name
  --list      print what would run, run nothing
  --windowed  run ONLY the windowed ones (needs a real desktop session)
  --all       run both headless and windowed
  --godot     Godot binary (default: $GODOT_BIN, else the project's known path)
"""

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SCRIPTS = REPO / "scripts" / "test"
SCENES = REPO / "scenes" / "test"

DEFAULT_GODOT = os.environ.get(
    "GODOT_BIN", r"E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe"
)

## Per-verification overrides, seconds. Anything generating a real map is slow;
## everything else should be quick, and a long run means something is wrong.
TIMEOUTS = {
    "verify_gates": 900,
    "verify_elevation": 900,
    "verify_mountain_ranges": 900,
    "verify_terrain_mesh": 600,
    "verify_save_screenshot": 600,
}
DEFAULT_TIMEOUT = 300


def kill_tree(pid: int) -> None:
    """Kill the process AND its children.

    Godot_..._console.exe spawns Godot_..._win64.exe as a child and waits on it.
    Killing only the direct child leaves the grandchild holding the stdout pipe open,
    so communicate() blocks forever afterwards -- measured at ~23 extra minutes on a
    300 s timeout before this was fixed. The timeout was, in effect, doing nothing.
    """
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)],
                       capture_output=True, check=False)
    else:
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


class Verification:
    def __init__(self, name: str, script: Path):
        self.name = name
        self.script = script
        self.scene = SCENES / (name + ".tscn")
        head = script.read_text(encoding="utf-8", errors="replace")[:4000]
        self.is_scene_tree = re.search(r"^extends\s+SceneTree", head, re.M) is not None
        ## The repo states this in the doc comment of every script that needs a real
        ## viewport; it is the only machine-readable signal available.
        self.windowed = re.search(r"NOT\s+--headless", head) is not None
        self.runnable = self.is_scene_tree or self.scene.is_file()

    def args(self, godot: str):
        target = (["-s", str(self.script.relative_to(REPO))] if self.is_scene_tree
                  else [str(self.scene.relative_to(REPO))])
        return [godot] + ([] if self.windowed else ["--headless"]) + target

    @property
    def mode(self):
        if self.windowed:
            return "window"
        return "-s" if self.is_scene_tree else "scene"

    @property
    def timeout(self):
        return TIMEOUTS.get(self.name, DEFAULT_TIMEOUT)


def discover(filters):
    out = []
    for script in sorted(SCRIPTS.glob("verify_*.gd")):
        if filters and not any(f in script.stem for f in filters):
            continue
        out.append(Verification(script.stem, script))
    return out


def run_one(v: Verification, godot: str):
    start = time.monotonic()
    try:
        proc = subprocess.Popen(
            v.args(godot), cwd=str(REPO),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace",
        )
    except FileNotFoundError:
        return 127, "Godot binary not found: %s\nSet GODOT_BIN or pass --godot." % godot, 0.0

    try:
        out, _ = proc.communicate(timeout=v.timeout)
        return proc.returncode, out or "", time.monotonic() - start
    except subprocess.TimeoutExpired:
        kill_tree(proc.pid)
        try:
            out, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            out = ""
        return 124, (out or "") + "\nTIMEOUT after %ds" % v.timeout, time.monotonic() - start


def tail(text: str, lines: int = 12) -> str:
    kept = [l for l in text.splitlines() if l.strip()]
    return "\n".join("      | " + l for l in kept[-lines:])


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("filters", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--windowed", action="store_true", help="run only the windowed ones")
    ap.add_argument("--all", action="store_true", help="run headless and windowed")
    ap.add_argument("--timeout", type=int, default=None, help="override every timeout")
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    args = ap.parse_args()

    ## Line-buffered so progress is visible when piped; the default full buffering
    ## made a 29-minute run look like a hang with zero output.
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass

    checks = discover(args.filters)
    if not checks:
        print("No verifications matched.")
        return 1

    if args.timeout:
        TIMEOUTS.clear()
        global DEFAULT_TIMEOUT
        DEFAULT_TIMEOUT = args.timeout

    if args.list:
        for v in checks:
            note = "" if v.runnable else "  (NOT RUNNABLE: extends Node with no scene)"
            print("%-32s %-7s timeout=%ds%s" % (v.name, v.mode, v.timeout, note))
        return 0

    if args.all:
        selected = checks
    elif args.windowed:
        selected = [v for v in checks if v.windowed]
    else:
        selected = [v for v in checks if not v.windowed]

    deferred = [v.name for v in checks if v not in selected]
    if not selected:
        print("Nothing to run in this mode. Deferred: %s" % ", ".join(deferred))
        return 0

    print("Running %d verifications with %s\n" % (len(selected), args.godot))
    failures, skipped = [], []

    for v in selected:
        if not v.runnable:
            print("  SKIP  %-32s no scenes/test/%s.tscn, and not a SceneTree script"
                  % (v.name, v.name))
            skipped.append(v.name)
            continue

        code, output, secs = run_one(v, args.godot)
        print("  %s  %-32s %6.1fs  (exit %d)"
              % ("ok  " if code == 0 else "FAIL", v.name, secs, code))
        if code != 0:
            failures.append(v.name)
            print(tail(output))

    print()
    if deferred:
        print("%d not run in this mode (use --windowed or --all): %s"
              % (len(deferred), ", ".join(deferred)))
    if skipped:
        print("%d skipped: %s" % (len(skipped), ", ".join(skipped)))
    if failures:
        print("FAILED (%d): %s" % (len(failures), ", ".join(failures)))
        return 1
    print("All %d verifications passed." % (len(selected) - len(skipped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
