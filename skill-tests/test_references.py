#!/usr/bin/env python3
"""Offline behavioral checks for the repository skill's reference files."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parent.parent
REFERENCES = ROOT / "references"


class SkillReferenceTest(unittest.TestCase):
    def test_referenced_files_exist(self):
        skill = (ROOT / "SKILL.md").read_text()
        paths = re.findall(r"`(references/[^`]+)`", skill)
        self.assertTrue(paths, "The skill must identify its reference files")
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file(), f"Missing reference: {path}")


class ReferenceTasksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(GOPROXY="off", GOSUMDB="off", GOTOOLCHAIN="local")
        with (REFERENCES / "mise.toml").open("rb") as source:
            self.tasks = tomllib.load(source)["tasks"]
        self.run_command("git", "init", "-q")

    def run_command(self, *args, **kwargs):
        return subprocess.run(
            args, cwd=self.project, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, **kwargs
        )

    def run_task(self, task, files=None, check=True):
        script = self.tasks[task]["run"]
        self.assertIsInstance(script, str)
        env = self.env | {"usage_staged_files": files or ""}
        return subprocess.run(
            ["bash", "-c", script], cwd=self.project, env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check
        )

    def test_setup_preserves_existing_hooks_and_invokes_hk(self):
        hooks = self.project / ".git" / "hooks"
        (hooks / "pre-commit").write_text("#!/bin/sh\n# LEFTHOOK\n")
        (hooks / "commit-msg").write_text("#!/bin/sh\n# custom hook\n")
        bin_dir = self.project / "bin"
        bin_dir.mkdir()
        mise = bin_dir / "mise"
        mise.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > mise-args\n")
        mise.chmod(0o755)
        self.env["PATH"] = f"{bin_dir}{os.pathsep}{self.env['PATH']}"
        self.run_task("setup")
        self.assertEqual((hooks / "pre-commit").read_text(), "#!/bin/sh\n# LEFTHOOK\n")
        self.assertEqual((hooks / "commit-msg").read_text(), "#!/bin/sh\n# custom hook\n")
        self.assertEqual((self.project / "mise-args").read_text().splitlines(),
                         ["exec", "--", "hk", "install", "--mise"])

    def test_go_fix_handles_files_in_multiple_directories(self):
        (self.project / "go.mod").write_text("module example.org/probe\n\ngo 1.26\n")
        (self.project / "main.go").write_text("package main\n\nvar Value interface{}\n")
        (self.project / "sub").mkdir()
        (self.project / "sub" / "sub.go").write_text("package sub\n\nvar Value interface{}\n")
        self.run_task("fix-go-fix", "main.go sub/sub.go")
        for path in (self.project / "main.go", self.project / "sub" / "sub.go"):
            self.assertIn("var Value any", path.read_text())

    def test_go_fix_check_reports_diff_without_writing(self):
        (self.project / "go.mod").write_text("module example.org/probe\n\ngo 1.26\n")
        path = self.project / "main.go"
        original = "package main\n\nvar Value interface{}\n"
        path.write_text(original)
        result = self.run_task("check-go-fix", "main.go", check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("any", result.stdout)
        self.assertEqual(path.read_text(), original)

    def test_go_and_markdown_tasks_ignore_other_file_types(self):
        (self.project / "README.md").write_text("# README\n")
        (self.project / "main.go").write_text("package main\n")
        for task in ("fix-gofumpt", "fix-goimports", "fix-go-fix", "fix-testifylint",
                     "check-gofumpt", "check-go-fix", "check-testifylint"):
            with self.subTest(task=task):
                self.run_task(task, "README.md")
        for task in ("fix-mdlint", "check-mdlint"):
            with self.subTest(task=task):
                self.run_task(task, "main.go")


if __name__ == "__main__":
    unittest.main()
