"""Regression tests for fail-closed adversarial orchestration; no model calls.

Run with: python -m unittest discover -s tools/adversarial -p test_run.py -v
"""

from __future__ import annotations

import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


RUNNER_PATH = Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("adversarial_runner_under_test", RUNNER_PATH)
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


def good_review() -> dict:
    return {
        "verdict": "pass",
        "summary": "Reviewed the change and its recorded verification results.",
        "evidence_complete": True,
        "findings": [],
    }


def envelope(review: dict | None = None, **overrides) -> str:
    value = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "structured_output": good_review() if review is None else review,
    }
    value.update(overrides)
    return json.dumps(value)


class ReviewParsingTests(unittest.TestCase):
    def test_valid_structured_result_is_extracted(self):
        self.assertEqual(runner.parse_review(envelope()), good_review())

    def test_missing_or_malformed_result_never_becomes_approval(self):
        for raw in ("", "approved", "null", "[]", "{}", '{"verdict":"pass"}',
                    envelope(structured_output=None), envelope(structured_output="pass")):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                runner.parse_review(raw)

    def test_error_envelope_cannot_smuggle_a_passing_review(self):
        for change in (
            {"is_error": True},
            {"subtype": "error_max_turns"},
            {"subtype": "error_max_structured_output_retries"},
            {"subtype": "error_during_execution"},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                runner.parse_review(envelope(**change))

    def test_review_requires_typed_evidence_and_findings(self):
        changes = (
            {"evidence_complete": "true"},
            {"verdict": "approved"},
            {"findings": "none"},
            {"summary": None},
            {"findings": [{"priority": "P1", "file": "app.py", "line": 0,
                            "issue": "Failure", "evidence": "Reproduction"}]},
        )
        for change in changes:
            review = good_review()
            review.update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                runner.parse_review(envelope(review))
        for key in good_review():
            review = good_review()
            del review[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                runner.parse_review(envelope(review))


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.checks = [{"name": name, "returncode": 0, "log": f"{name}.log"}
                       for name in sorted(runner.GATE_NAMES)]

    def test_complete_review_and_successful_checks_pass(self):
        self.assertTrue(runner.review_passed(good_review(), self.checks))

    def test_test_failure_overrides_model_approval(self):
        checks = copy.deepcopy(self.checks)
        checks.append({"name": "regression", "returncode": 1, "log": "failed.log"})
        self.assertFalse(runner.review_passed(good_review(), checks))

    def test_incomplete_review_or_nonpassing_verdict_cannot_pass(self):
        for change in ({"evidence_complete": False}, {"verdict": "blocked"},
                       {"verdict": "changes_required"}):
            review = good_review()
            review.update(change)
            with self.subTest(change=change):
                self.assertFalse(runner.review_passed(review, self.checks))

    def test_no_checks_is_not_successful_validation(self):
        self.assertFalse(runner.review_passed(good_review(), []))

    def test_missing_required_gate_or_any_finding_blocks_approval(self):
        self.assertFalse(runner.review_passed(good_review(), self.checks[:-1]))
        review = good_review()
        review["findings"] = [{"priority": "P3", "file": "app.py", "line": 1,
                               "issue": "Concrete issue", "evidence": "Reproduction"}]
        self.assertFalse(runner.review_passed(review, self.checks))


class TemporaryRepository(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="adversarial-tests-")
        self.root = Path(self.temp.name).resolve()
        self.assertEqual(self.root.parent, Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.cleanup_temp)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Runner Tests")
        self.git("config", "user.email", "tests@example.invalid")
        (self.repo / "app.py").write_text("value = 1\n", encoding="utf-8")
        self.git("add", "app.py")
        self.git("-c", "user.name=Runner Tests", "-c", "user.email=tests@example.invalid",
                 "commit", "-qm", "fixture")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def cleanup_temp(self):
        # Recursive cleanup is restricted to the exact test-created temp directory.
        resolved = Path(self.temp.name).resolve()
        if resolved != self.root or resolved.parent != Path(tempfile.gettempdir()).resolve():
            raise AssertionError("Refusing to clean an unexpected temporary directory")
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True, text=True,
                              encoding="utf-8", capture_output=True, shell=False)


class SnapshotTests(TemporaryRepository):
    def test_fingerprint_detects_edits_new_files_and_deleted_files(self):
        original = runner.source_fingerprint(self.repo)
        (self.repo / "app.py").write_text("value = 2\n", encoding="utf-8")
        edited = runner.source_fingerprint(self.repo)
        self.assertNotEqual(original, edited)
        (self.repo / "new.py").write_text("unexpected = True\n", encoding="utf-8")
        added = runner.source_fingerprint(self.repo)
        self.assertNotEqual(edited, added)
        (self.repo / "app.py").unlink()
        self.assertNotEqual(added, runner.source_fingerprint(self.repo))

    def test_review_diff_includes_untracked_source(self):
        (self.repo / "app.py").write_text("value = 2\n", encoding="utf-8")
        (self.repo / "new.py").write_text("important_new_behavior = True\n", encoding="utf-8")
        diff = runner.collect_diff(self.repo, self.base)
        self.assertIn("value = 2", diff)
        self.assertIn("important_new_behavior = True", diff)
        self.assertIn("new.py", diff)

    def test_oversized_diff_fails_instead_of_silently_truncating(self):
        (self.repo / "app.py").write_text("changed = True\n" * 100, encoding="utf-8")
        with self.assertRaises(ValueError):
            runner.collect_diff(self.repo, self.base, max_bytes=32)


class CommandTests(unittest.TestCase):
    def test_arguments_are_passed_literally_without_shell_expansion(self):
        values = ["two words", 'quote\"inside', "$(echo unsafe)", "a&b", "a|b", "雪"]
        result = runner.run_command(
            [sys.executable, "-c", "import json,sys; print(json.dumps(sys.argv[1:]))", *values],
            cwd=Path.cwd(), timeout=10,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), values)

    def test_expired_total_deadline_prevents_another_process(self):
        with mock.patch.object(runner, "RUN_DEADLINE", 0), \
                mock.patch.object(runner.subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(RuntimeError, "run_timeout"):
                runner.run_command([sys.executable, "--version"], Path.cwd(), 10)
        spawn.assert_not_called()

    def test_codex_review_command_uses_schema_file_and_read_only_sandbox(self):
        command = runner.reviewer_command("codex.exe", Path("result.json"), Path("schema.json"))
        self.assertEqual(command[command.index("--sandbox") + 1], "read-only")
        self.assertEqual(command[command.index("--output-schema") + 1], "schema.json")
        self.assertEqual(command[command.index("-o") + 1], "result.json")
        self.assertEqual(command[command.index("-a") + 1], "never")
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", command)


BACKLOG_ANCHOR = "| 1 Navigation | Fix navigation edge case [gated] | Reproducible |"


def selected_task():
    return {
        "decision": "task", "task_id": "navigation-edge-case", "title": "Navigation edge case",
        "task": "Fix the navigation edge case with before and after scenario evidence.",
        "acceptance_criteria": ["The reproducible scenario succeeds."],
        "evidence_plan": ["Record the scenario before and after the change."],
        "tag": "gated", "reason": "Highest priority eligible issue.",
        "backlog_anchor": BACKLOG_ANCHOR, "priority": 1,
    }


class SelectionTests(TemporaryRepository):
    def setUp(self):
        super().setUp()
        (self.repo / "backlog.md").write_text("## Now\n\n" + BACKLOG_ANCHOR + "\n", encoding="utf-8")
        self.git("add", "backlog.md")
        self.git("commit", "-qm", "backlog fixture")

    def select(self, selection, history=None, mutate=False):
        original = runner.run_command

        def fake_command(argv, cwd, timeout, input_text=None, log_path=None):
            if argv[0] == "git":
                return original(argv, cwd, timeout, input_text, log_path)
            if mutate:
                (Path(cwd) / "app.py").write_text("unexpected = True\n", encoding="utf-8")
            return subprocess.CompletedProcess(argv, 0, stdout=envelope(selection))

        with mock.patch.object(runner, "run_command", side_effect=fake_command):
            return runner.select_task("claude.exe", self.repo, history or [], 10, self.root / "selection.json")

    def test_valid_selector_output_is_bound_to_committed_backlog_row(self):
        self.assertEqual(self.select(selected_task()), selected_task())

    def test_invented_anchor_or_wrong_priority_is_rejected(self):
        for change in ({"backlog_anchor": "an invented task"}, {"priority": 2}, {"priority": True},
                       {"tag": "visual-human"}, {"evidence_plan": []}):
            selection = selected_task()
            selection.update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.select(selection)

    def test_no_task_requires_empty_task_fields(self):
        no_task = {"decision": "no_eligible_task", "task_id": "", "title": "", "task": "",
                   "acceptance_criteria": [], "evidence_plan": [], "tag": "none",
                   "reason": "Required scenario evidence cannot be obtained.",
                   "backlog_anchor": "", "priority": 0}
        self.assertIsNone(self.select(no_task))
        for change in ({"task": "Do something anyway"}, {"priority": False}, {"tag": "gated"},
                       {"evidence_plan": ["unexpected"]}, {"reason": ""}):
            invalid = dict(no_task, **change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.select(invalid)

    def test_completed_task_is_not_selected_again(self):
        with self.assertRaisesRegex(ValueError, "repeated"):
            self.select(selected_task(), history=[selected_task()])

    def test_selector_modifying_source_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "changed the worktree"):
            self.select(selected_task(), mutate=True)


class PersistenceTests(TemporaryRepository):
    def test_lock_rejects_overlap_and_releases_after_exception(self):
        with self.assertRaisesRegex(RuntimeError, "intentional"):
            with runner.auto_lock(self.repo):
                with self.assertRaisesRegex(RuntimeError, "auto_already_running"):
                    with runner.auto_lock(self.repo):
                        self.fail("Overlapping autopilot acquired the lock")
                raise RuntimeError("intentional")
        with runner.auto_lock(self.repo):
            pass

    def test_report_replacement_preserves_old_state_when_atomic_replace_fails(self):
        state = self.root / "state.json"
        runner.write_json(state, {"status": "old"})
        with mock.patch.object(runner.os, "replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                runner.write_json(state, {"status": "new"})
        self.assertEqual(json.loads(state.read_text()), {"status": "old"})

    def test_auto_rejects_invalid_deadlines_before_starting_work(self):
        for flag, value in (("--run-timeout", "0"), ("--run-timeout", "16201"), ("--timeout", "0")):
            with self.subTest(flag=flag, value=value), \
                    mock.patch.object(runner, "run_workflow") as workflow, \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(runner.main(["auto", "--repo", str(self.repo), flag, value]), 1)
                workflow.assert_not_called()
                self.assertIsNone(runner.RUN_DEADLINE)


class PullRequestPublishingTests(TemporaryRepository):
    def test_pushes_then_creates_a_pull_request_with_literal_arguments(self):
        selected = selected_task()
        report_dir = self.root / "report"
        calls = []

        def fake_command(argv, cwd, timeout, input_text=None, log_path=None):
            calls.append(list(argv))
            if argv[:3] == ["gh.exe", "pr", "list"]:
                output = "[]"
            elif argv[:3] == ["gh.exe", "pr", "create"]:
                output = "https://example.invalid/owner/repo/pull/42\n"
            else:
                output = ""
            if log_path:
                Path(log_path).write_text(output, encoding="utf-8")
            return subprocess.CompletedProcess(argv, 0, stdout=output)

        with mock.patch.object(runner, "run_command", side_effect=fake_command):
            published = runner.publish_pull_request(
                self.repo, "codex/adversarial-autopilot", "master", selected, report_dir, "gh.exe")
        self.assertEqual(published, {"url": "https://example.invalid/owner/repo/pull/42", "created": True})
        self.assertEqual(calls[0], ["git", "push", "--set-upstream", "origin", "codex/adversarial-autopilot"])
        self.assertEqual(calls[1], ["gh.exe", "pr", "list", "--head", "codex/adversarial-autopilot",
                                    "--base", "master", "--state", "open", "--json", "url"])
        self.assertIn("--body-file", calls[2])

    def test_reuses_an_existing_open_pull_request_without_creating_another(self):
        selected = selected_task()
        report_dir = self.root / "report"

        def fake_command(argv, cwd, timeout, input_text=None, log_path=None):
            output = '[{"url":"https://example.invalid/owner/repo/pull/7"}]' if argv[:3] == ["gh.exe", "pr", "list"] else ""
            if log_path:
                Path(log_path).write_text(output, encoding="utf-8")
            return subprocess.CompletedProcess(argv, 0, stdout=output)

        with mock.patch.object(runner, "run_command", side_effect=fake_command):
            published = runner.publish_pull_request(
                self.repo, "codex/adversarial-autopilot", "master", selected, report_dir, "gh.exe")
        self.assertEqual(published, {"url": "https://example.invalid/owner/repo/pull/7", "created": False})



class WorkflowTests(TemporaryRepository):
    """Exercise real Git worktrees and reports, substituting only models and gates."""

    def setUp(self):
        super().setUp()
        (self.repo / "backlog.md").write_text("## Now\n\n" + BACKLOG_ANCHOR + "\n", encoding="utf-8")
        (self.repo / ".gitignore").write_text(".adversarial/\n", encoding="utf-8")
        self.git("add", ".gitignore", "backlog.md")
        self.git("commit", "-qm", "ignore runner evidence")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        (self.repo / "app.py").write_text("user_uncommitted_work = True\n", encoding="utf-8")
        self.primary_content = (self.repo / "app.py").read_bytes()
        self.model_calls = []

    def execute(self, *, baseline_failure=False, gate_failure=False, protected=False,
                reviewer_mutation=False, malformed_review=False, missing_review=False):
        original = runner.run_command

        def fake_command(argv, cwd, timeout, input_text=None, log_path=None):
            if argv[0] == "git":
                return original(argv, cwd, timeout, input_text, log_path)
            cwd = Path(cwd)
            if argv[0] == "claude.exe" and "--json-schema" in argv:
                self.model_calls.append("selector")
                stdout = envelope(selected_task())
            elif argv[0] == "claude.exe":
                self.model_calls.append("builder")
                target = cwd / ("tools/ci/unsafe.py" if protected else "app.py")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("value = 2\n", encoding="utf-8")
                stdout = json.dumps({"is_error": False, "subtype": "success", "result": "Implemented and verified."})
            elif argv[0] == "codex.exe":
                self.model_calls.append("reviewer")
                output = Path(argv[argv.index("-o") + 1])
                if not missing_review:
                    output.write_text("approved" if malformed_review else json.dumps(good_review()), encoding="utf-8")
                if reviewer_mutation:
                    (cwd / "app.py").write_text("reviewer_changed_source = True\n", encoding="utf-8")
                stdout = '{"type":"turn.completed"}\n'
            else:
                raise AssertionError(f"Unexpected external command: {argv}")
            if log_path:
                Path(log_path).write_text(stdout, encoding="utf-8")
            return subprocess.CompletedProcess(argv, 0, stdout=stdout)

        def fake_checks(worktree, godot, timeout, directory, import_first=False):
            failure = baseline_failure if directory.name == "baseline" else gate_failure
            for name in sorted(runner.GATE_NAMES):
                (directory / f"{name}.log").write_text("Mock verification evidence.\n", encoding="utf-8")
            return [{"name": name, "returncode": int(failure and name == "gdscript"),
                     "log": str(directory / f"{name}.log")} for name in sorted(runner.GATE_NAMES)]

        with mock.patch.object(runner, "discover_executable", side_effect=lambda name, override=None: name + ".exe"), \
                mock.patch.object(runner, "preflight", return_value={"authentication": "mocked"}), \
                mock.patch.object(runner, "run_command", side_effect=fake_command), \
                mock.patch.object(runner, "run_checks", side_effect=fake_checks), \
                contextlib.redirect_stdout(io.StringIO()):
            result = runner.main(["auto", "--repo", str(self.repo), "--max-rounds", "2", "--run-timeout", "60"])
        self.assertEqual((self.repo / "app.py").read_bytes(), self.primary_content)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.base)
        reports = list((self.repo / ".adversarial/runs").glob("*/report.json"))
        self.assertEqual(len(reports), 1)
        return result, json.loads(reports[0].read_text(encoding="utf-8"))

    def test_success_commits_only_in_autopilot_and_persists_history(self):
        code, report = self.execute()
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "passed")
        self.assertNotEqual(report["commit"], self.base)
        committed_files = self.git("ls-tree", "-r", "--name-only", report["commit"]).stdout.splitlines()
        self.assertFalse(any(name.startswith(".adversarial/") for name in committed_files))
        self.assertEqual(self.git("show", report["commit"] + ":app.py").stdout, "value = 2\n")
        history = json.loads((self.repo / ".adversarial/auto-state.json").read_text())
        self.assertEqual(history["branches"]["codex/adversarial-autopilot"][0]["task_id"], selected_task()["task_id"])
        self.assertEqual(self.model_calls, ["selector", "builder", "reviewer"])

    def test_baseline_failure_stops_before_any_model_call(self):
        code, report = self.execute(baseline_failure=True)
        self.assertEqual((code, report["status"]), (1, "baseline_failed"))
        self.assertEqual(self.model_calls, [])

    def test_failing_gates_override_repeated_model_approval_and_stop_at_round_limit(self):
        code, report = self.execute(gate_failure=True)
        self.assertEqual((code, report["status"]), (1, "rounds_exhausted"), report)
        self.assertEqual(self.model_calls.count("builder"), 2)
        self.assertEqual(self.model_calls.count("reviewer"), 2)
        self.assertNotIn("commit", report)

    def test_protected_gate_edits_block_before_review(self):
        code, report = self.execute(protected=True)
        self.assertEqual((code, report["status"]), (1, "blocked"))
        self.assertNotIn("reviewer", self.model_calls)

    def test_reviewer_source_mutation_blocks_passing_verdict(self):
        code, report = self.execute(reviewer_mutation=True)
        self.assertEqual((code, report["status"]), (1, "reviewer_modified_files"))

    def test_malformed_codex_output_fails_closed(self):
        code, report = self.execute(malformed_review=True)
        self.assertEqual((code, report["status"]), (1, "review_failed"))

    def test_missing_codex_output_cannot_count_as_pass(self):
        code, report = self.execute(missing_review=True)
        self.assertEqual(code, 1)
        self.assertNotEqual(report["status"], "passed")
        self.assertNotIn("commit", report)


if __name__ == "__main__":
    unittest.main()
