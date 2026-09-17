#!/usr/bin/env python3
"""Run the deterministic playtest scenarios and collect their evidence.

Each scenario boots the real Main.tscn, scripts a player's actions, drives time at
a fixed step, and writes JSON: experience checks keyed to PLAYER_EXPERIENCE.md's
acceptance criteria, plus GameplayTelemetry. See scripts/test/playtest/playtest_runner.gd.

NOT a gate. Exit code is non-zero only when a scenario failed to RUN (crash,
timeout, no JSON written). A scenario full of "concern" rows exited 0 on purpose:
telemetry is evidence, not a score, and a boring result is a finding.

Usage:
  python3 tools/playtest/run_scenarios.py [--list] [--shots] [--godot PATH] [NAME[:VARIANT] ...]

  NAME[:VARIANT]  scenario to run, e.g. `horde:dark`; default is the full set below
  --shots         run windowed and capture screenshots at each scenario's checkpoints
                  (needs a real desktop session; a headless viewport has no texture)
  --summary       print only the check table from existing results, run nothing

Results land in playtest_results/<name>[_<variant>].json (gitignored) and a
one-line-per-check table is printed at the end, so a before/after comparison is two
runs and a diff.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
OUT = REPO / "playtest_results"
DEFAULT_GODOT = os.environ.get(
    "GODOT_BIN", r"E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe"
)

## The default set: every scenario once, plus the going-dark variant of the horde,
## because the difference between `horde` and `horde:dark` is the measurement.
DEFAULT_SET = ["opening", "expansion", "horde", "horde:dark", "siege", "industrialisation"]
TIMEOUT_SECONDS = 1800
NO_PROPS = False  ## --no-props: see playtest_runner.gd.


def kill_tree(pid: int) -> None:
    """Godot_..._console.exe spawns the real Godot as a child; kill both (see
    tools/ci/run_verifications.py's kill_tree for the measured cost of not doing so)."""
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True, check=False)
    else:
        proc_kill = subprocess.run(["pkill", "-P", str(pid)], capture_output=True, check=False)
        os.kill(pid, 9)


def result_path(name: str, variant: str) -> Path:
    return OUT / ("%s%s.json" % (name, "_" + variant if variant else ""))


def run(spec: str, godot: str, shots: bool) -> bool:
    name, _, variant = spec.partition(":")
    path = result_path(name, variant)
    if path.exists():
        path.unlink()
    args = [godot, "--path", str(REPO)]
    if not shots:
        args.append("--headless")
    args += ["res://scenes/test/playtest_runner.tscn", "--",
             "--scenario=" + name, "--out=" + str(path).replace("\\", "/")]
    if variant:
        args.append("--variant=" + variant)
    if shots:
        args.append("--shots")
    if NO_PROPS:
        args.append("--no-props")

    log_path = OUT / ("%s%s.log" % (name, "_" + variant if variant else ""))
    start = time.monotonic()
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.Popen(args, cwd=str(REPO), stdout=log, stderr=subprocess.STDOUT)
        code = None
        ## A GDScript parse error leaves Godot idling on an empty scene instead of
        ## exiting, so the log is watched and the run is killed on one rather than
        ## waiting out TIMEOUT_SECONDS.
        while code is None:
            time.sleep(2.0)
            code = proc.poll()
            text = log_path.read_text(encoding="utf-8", errors="replace")
            if code is None and ("Parse Error" in text or time.monotonic() - start > TIMEOUT_SECONDS):
                kill_tree(proc.pid)
                code = 125 if "Parse Error" in text else 124
    secs = time.monotonic() - start
    ok = code == 0 and path.exists()
    print("  %s  %-24s %6.1fs  (exit %d)  log: %s" % ("ran " if ok else "FAIL", spec, secs, code,
                                                     log_path.relative_to(REPO)))
    return ok


def summarise(specs) -> None:
    print()
    for spec in specs:
        name, _, variant = spec.partition(":")
        path = result_path(name, variant)
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        print("%s%s" % (name, " [" + variant + "]" if variant else ""))
        for row in data.get("experience_checks", []):
            measured = row.get("measured")
            if not isinstance(measured, str):
                measured = "(see JSON)"
            print("  %-7s %-8s %s -> %s" % (row["criterion"], row["status"], row["question"], measured))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--shots", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--no-props", action="store_true", help="drop terrain props even with --shots, for scenarios whose units walk")
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    args = ap.parse_args()
    global NO_PROPS
    NO_PROPS = args.no_props
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass

    specs = args.scenarios or DEFAULT_SET
    if args.list:
        print("\n".join(DEFAULT_SET))
        return 0
    OUT.mkdir(exist_ok=True)
    if args.summary:
        summarise(specs)
        return 0

    print("Running %d scenarios with %s\n" % (len(specs), args.godot))
    failed = [s for s in specs if not run(s, args.godot, args.shots)]
    summarise(specs)
    if failed:
        print("\nDID NOT RUN: %s" % ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
