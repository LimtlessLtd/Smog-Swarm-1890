#!/usr/bin/env python3
"""Lightweight, Godot-binary-free sanity checks for this project's GDScript
and scene files.

No Godot editor/CLI is available in the environment these checks were
authored in (an agent-driven remote session with no network access to fetch
an engine binary), so every previous phase's GDScript was reviewed by hand
against the same handful of mistakes this script now automates: unbalanced
brackets, space-mixed-with-tab indentation (the project's own convention is
tabs only), duplicate `class_name` declarations (Godot requires these to be
globally unique and fails to load the project otherwise), the specific
"StringName literal directly followed by the `%` format operator" bug that
came up during Phase 2.9 (StringName has no `%` operator overload — only
String does), and scene files whose `ext_resource`/`sub_resource` paths
point at files that don't actually exist on disk (a silent scene-load
failure at runtime).

This is deliberately NOT a substitute for actually opening the project in
the editor or running it headless — it only catches the mistakes it knows
to look for. Treat a clean run as "no known red flags", not "verified
correct".
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

CLASS_NAME_RE = re.compile(r'^class_name\s+(\w+)', re.MULTILINE)
STRINGNAME_FORMAT_BUG_RE = re.compile(r'&"[^"]*"\s*%')
RES_PATH_RE = re.compile(r'path="(res://[^"]+)"')

BRACKET_PAIRS = {'(': ')', '[': ']', '{': '}'}
CLOSERS = {v: k for k, v in BRACKET_PAIRS.items()}


def strip_noise(source: str) -> str:
    """Removes comments and string-literal contents so bracket-counting
    and other structural checks don't get confused by a `(` inside a
    string or a comment. A single quote-aware left-to-right pass (NOT two
    independent regex substitutions) — a previous two-pass version
    stripped comments first via a naive `#.*$` regex, which broke on a
    `#` inside a string literal (e.g. `Color("#1f150f")`, once real code
    started using hex-string colors): it truncated the line right after
    the opening quote, losing the closing `")` and producing a false
    "unbalanced '(' (never closed)". Scanning char-by-char and tracking
    "currently inside a string" state fixes that (a `#` only starts a
    comment when not inside a string) while still avoiding the OTHER
    failure mode two-pass stripping was originally guarding against (a
    stray quote inside a comment, e.g. `## "Church Steeple Watchtower"`,
    pairing up with an unrelated quote later in the file) — comments are
    still recognized and skipped before any quote character inside them
    gets a chance to open a string, since scanning is left-to-right and
    the `#` is hit first. Every newline is preserved exactly (even while
    "inside" a string or a stripped comment) so downstream line numbers
    stay accurate. Deliberately crude (doesn't special-case GDScript's
    triple-quoted strings) — good enough for a sanity check, not a real
    parser."""
    result: list[str] = []
    i = 0
    n = len(source)
    quote: str | None = None  # the quote character currently open, or None
    while i < n:
        ch = source[i]
        if quote:
            if ch == '\\' and i + 1 < n and source[i + 1] != '\n':
                i += 2  # skip an escaped char (e.g. \") so it can't end the string early
                continue
            if ch == quote:
                quote = None
            elif ch == '\n':
                result.append('\n')  # unterminated string spanning a line break: don't eat the newline
            i += 1
            continue
        if ch == '"' or ch == "'":
            quote = ch
            i += 1
            continue
        if ch == '#':
            while i < n and source[i] != '\n':
                i += 1
            continue
        result.append(ch)
        i += 1
    return ''.join(result)


def check_brackets(path: Path, cleaned: str) -> list[str]:
    errors = []
    stack: list[tuple[str, int]] = []
    line_no = 1
    for ch in cleaned:
        if ch == '\n':
            line_no += 1
            continue
        if ch in BRACKET_PAIRS:
            stack.append((ch, line_no))
        elif ch in CLOSERS:
            if not stack or stack[-1][0] != CLOSERS[ch]:
                errors.append(f"{path}:{line_no}: unbalanced '{ch}' (no matching '{CLOSERS[ch]}' open)")
                return errors
            stack.pop()
    for ch, opened_line in stack:
        errors.append(f"{path}:{opened_line}: unbalanced '{ch}' (never closed)")
    return errors


def check_indentation(path: Path, raw: str) -> list[str]:
    errors = []
    for line_no, line in enumerate(raw.split('\n'), start=1):
        stripped = line.lstrip(' \t')
        if not stripped or stripped.startswith('#'):
            continue
        leading = line[: len(line) - len(stripped)]
        if ' ' in leading and '\t' in leading:
            errors.append(f"{path}:{line_no}: mixed tab/space indentation")
        elif leading.startswith(' ') and stripped:
            errors.append(f"{path}:{line_no}: space indentation (project convention is tabs)")
    return errors


def check_stringname_format_bug(path: Path, raw: str) -> list[str]:
    errors = []
    for line_no, line in enumerate(raw.split('\n'), start=1):
        if STRINGNAME_FORMAT_BUG_RE.search(line):
            errors.append(
                f"{path}:{line_no}: StringName literal (&\"...\") directly followed by '%' — "
                "StringName has no % format operator, build a String first (e.g. "
                'StringName("foo_%d" % n))'
            )
    return errors


def check_scene_resource_paths(path: Path, raw: str) -> list[str]:
    errors = []
    for line_no, line in enumerate(raw.split('\n'), start=1):
        for match in RES_PATH_RE.finditer(line):
            res_path = match.group(1)
            local_path = REPO_ROOT / res_path[len('res://'):]
            if not local_path.exists():
                errors.append(f"{path}:{line_no}: referenced path does not exist on disk: {res_path}")
    return errors


def main() -> int:
    gd_files = sorted(REPO_ROOT.glob('scripts/**/*.gd'))
    scene_files = sorted(REPO_ROOT.glob('scenes/**/*.tscn')) + sorted(REPO_ROOT.glob('**/*.tres'))

    all_errors: list[str] = []
    class_names: dict[str, Path] = {}

    for path in gd_files:
        rel_path = path.relative_to(REPO_ROOT)
        raw = path.read_text(encoding='utf-8')
        cleaned = strip_noise(raw)

        all_errors.extend(check_brackets(rel_path, cleaned))
        all_errors.extend(check_indentation(rel_path, raw))
        all_errors.extend(check_stringname_format_bug(rel_path, raw))

        for match in CLASS_NAME_RE.finditer(raw):
            name = match.group(1)
            if name in class_names:
                all_errors.append(
                    f"{rel_path}: duplicate class_name '{name}' (already declared in {class_names[name]})"
                )
            else:
                class_names[name] = rel_path

    for path in scene_files:
        rel_path = path.relative_to(REPO_ROOT)
        raw = path.read_text(encoding='utf-8')
        all_errors.extend(check_scene_resource_paths(rel_path, raw))

    print(f"Checked {len(gd_files)} .gd files and {len(scene_files)} scene/resource files.")

    if all_errors:
        print(f"\n{len(all_errors)} issue(s) found:\n")
        for error in all_errors:
            print(f"  {error}")
        return 1

    print("No issues found.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
