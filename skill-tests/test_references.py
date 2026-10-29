#!/usr/bin/env python3
"""Reference links and opt-in behavioral checks against installed hk tools.

Run verify-tasks.sh to install tools and enable the integration cases.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SKILL_DIR = ROOT / "skills" / "go-template"
REFERENCES = SKILL_DIR / "references"
FIXTURE = os.environ.get("GO_TEMPLATE_TEST_PROJECT")


class SkillReferenceTest(unittest.TestCase):
	def test_referenced_files_exist(self) -> None:
		skill = (SKILL_DIR / "SKILL.md").read_text()
		paths = re.findall(r"`(references/[^`]+)`", skill)
		self.assertTrue(paths, "The skill must identify its reference files")
		for path in paths:
			with self.subTest(path=path):
				self.assertTrue((SKILL_DIR / path).is_file(), f"Missing reference: {path}")


@unittest.skipUnless(FIXTURE, "Run skill-tests/verify-tasks.sh for hk integration tests")
class HkEntryPointTest(unittest.TestCase):
	def setUp(self) -> None:
		self.tmp = tempfile.TemporaryDirectory()
		self.addCleanup(self.tmp.cleanup)
		self.project = Path(self.tmp.name)
		shutil.copytree(FIXTURE, self.project, dirs_exist_ok=True,
		                ignore=shutil.ignore_patterns(".git"))
		self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
		self.env.update(MISE_TRUSTED_CONFIG_PATHS=str(self.project), HK_MISE="1")
		self.run_command("git", "init", "-q")
		self.run_command("git", "config", "user.name", "Integration Test")
		self.run_command("git", "config", "user.email", "integration@example.invalid")
		self.run_command("git", "add", ".")
		self.run_command("git", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "Baseline")

	def run_command(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
		result = subprocess.run(args, cwd=self.project, env=self.env, text=True,
		                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
		if check:
			self.assertEqual(result.returncode, 0, f"{args!r}\n{result.stdout}")
		return result

	def hk(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
		return self.run_command("mise", "exec", "--", "hk", *args, check=check)

	def snapshot(self) -> dict[str, bytes]:
		return {str(path.relative_to(self.project)): path.read_bytes()
		        for path in self.project.rglob("*")
		        if path.is_file() and ".git" not in path.relative_to(self.project).parts}

	def write_dirty_formats(self) -> dict[str, str]:
		files = {
			"format.go": "package  main\n\nfunc   F( ) {}\n",
			"format.pkl": 'name="demo"\n',
			"format.toml": 'name   =    "demo"\n',
			"format.yaml": "name:    demo\n",
			"format.md": "#  Title\n",
		}
		for name, content in files.items():
			(self.project / name).write_text(content)
		return files

	def test_check_reports_format_errors_without_mutating_files_or_index(self) -> None:
		files = self.write_dirty_formats()
		self.run_command("git", "add", *files)
		before = self.snapshot()
		index = self.run_command("git", "write-tree").stdout
		# Exercise each format separately: one failing formatter must not hide another.
		for name in files:
			with self.subTest(name=name):
				result = self.hk("check", name, check=False)
				self.assertNotEqual(result.returncode, 0, result.stdout)
				self.assertEqual(self.snapshot(), before, result.stdout)
				self.assertEqual(self.run_command("git", "write-tree").stdout, index)

	def test_fix_formats_go_pkl_toml_yaml_and_markdown(self) -> None:
		files = self.write_dirty_formats()
		self.hk("fix", *files)
		expected = {
			"format.go": "package main\n\nfunc F() {}\n",
			"format.pkl": 'name = "demo"\n',
			"format.toml": 'name = "demo"\n',
			"format.yaml": "name: demo\n",
			"format.md": "# Title\n",
		}
		for name, content in expected.items():
			with self.subTest(name=name):
				self.assertEqual((self.project / name).read_text(), content)
		self.hk("check", *files)

	def test_go_fix_handles_multiple_directories(self) -> None:
		(self.project / "sub").mkdir()
		for name, package in (("modern.go", "main"), ("sub/modern.go", "sub")):
			(self.project / name).write_text(f"package {package}\n\nvar Value interface{{}}\n")
		# Scoped fixes must not run module-wide Go writers.
		before = self.snapshot()
		result = self.hk("fix", "modern.go", "sub/modern.go", check=False)
		self.assertNotEqual(result.returncode, 0, result.stdout)
		self.assertEqual(self.snapshot(), before)
		self.run_command("mise", "run", "fix")
		for name in ("modern.go", "sub/modern.go"):
			self.assertIn("var Value any", (self.project / name).read_text())
		self.run_command("mise", "run", "test")

	def test_full_fix_tidies_go_mod(self) -> None:
		path = self.project / "go.mod"
		path.write_text(path.read_text() + "\nrequire example.invalid/unused v1.0.0\n")
		self.run_command("mise", "run", "fix")
		self.assertNotIn("example.invalid/unused", path.read_text())

	def test_installed_pre_commit_blocks_secret_in_plain_text(self) -> None:
		self.run_command("mise", "run", "setup")
		path = self.project / "secret.txt"
		# A successful control commit rules out unrelated installation failures.
		path.write_text("No credentials here.\n")
		self.run_command("git", "add", path.name)
		self.run_command("git", "commit", "-qm", "Safe plain text")
		head = self.run_command("git", "rev-parse", "HEAD").stdout
		fake_key = "AKIA" + "Q7M3XNB5TRW2KHLD"
		path.write_text(f'aws = "{fake_key}"\n')
		self.run_command("git", "add", path.name)
		result = self.run_command("git", "commit", "-qm", "Reject credential", check=False)
		self.assertNotEqual(result.returncode, 0, result.stdout)
		self.assertIn("gitleaks", result.stdout.lower())
		self.assertEqual(self.run_command("git", "rev-parse", "HEAD").stdout, head)

	def test_pre_commit_formats_and_stages_only_selected_files(self) -> None:
		(self.project / "staged.md").write_text("#  Staged\n")
		(self.project / "unstaged.md").write_text("# Unstaged\n")
		self.run_command("git", "add", "staged.md", "unstaged.md")
		self.run_command("git", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "Staging fixture")
		(self.project / "staged.md").write_text("#  Changed\n")
		self.run_command("git", "add", "staged.md")
		(self.project / "unstaged.md").write_text("#  Untouched\n")
		(self.project / "untracked.md").write_text("#  Untracked\n")
		formats = self.write_dirty_formats()
		self.run_command("git", "add", *formats)
		self.run_command("mise", "run", "setup")
		self.run_command("git", "hook", "run", "pre-commit")
		for name, original in formats.items():
			with self.subTest(name=name):
				formatted = (self.project / name).read_text()
				self.assertNotEqual(formatted, original)
				self.assertEqual(self.run_command("git", "show", f":{name}").stdout, formatted)
		self.assertEqual((self.project / "staged.md").read_text(), "# Changed\n")
		self.assertEqual(self.run_command("git", "show", ":staged.md").stdout, "# Changed\n")
		self.assertEqual((self.project / "unstaged.md").read_text(), "#  Untouched\n")
		self.assertEqual(self.run_command("git", "show", ":unstaged.md").stdout, "# Unstaged\n")
		self.assertEqual((self.project / "untracked.md").read_text(), "#  Untracked\n")
		self.assertEqual(set(self.run_command("git", "diff", "--cached", "--name-only").stdout.splitlines()),
		                 {"staged.md", *formats})

	def test_full_fix_repairs_unused_imports_before_analysis(self) -> None:
		path = self.project / "imports.go"
		path.write_text('package main\n\nimport "fmt"\n\nfunc Unused() {}\n')
		self.run_command("mise", "run", "fix")
		self.assertNotIn('"fmt"', path.read_text())
		self.run_command("mise", "run", "check")

	def test_pre_commit_blocks_secret_in_binary_staged_bytes(self) -> None:
		self.run_command("mise", "run", "setup")
		control = self.project / "control.txt"
		control.write_text("No credentials here.\n")
		self.run_command("git", "add", control.name)
		self.run_command("git", "commit", "-qm", "Safe control")
		head = self.run_command("git", "rev-parse", "HEAD").stdout
		path = self.project / "secret.dat"
		# Split so this source file carries no detectable secret itself.
		key = "AKIA" + "Q7M3XNB5TRW2KHLD"
		path.write_bytes(b"PREFIX\x00awsToken = " + key.encode() + b"\n")
		self.run_command("git", "add", path.name)
		result = self.run_command("git", "commit", "-qm", "Reject binary credential", check=False)
		self.assertNotEqual(result.returncode, 0, result.stdout)
		self.assertIn("gitleaks", result.stdout.lower())
		self.assertEqual(self.run_command("git", "rev-parse", "HEAD").stdout, head)

	def test_setup_preserves_existing_hooks(self) -> None:
		hooks = self.project / ".git" / "hooks"
		existing = {"pre-commit": "#!/bin/sh\n# LEFTHOOK\n", "commit-msg": "#!/bin/sh\n# custom hook\n"}
		for name, content in existing.items():
			(hooks / name).write_text(content)
		# Refusing installation is allowed. Silently deleting hooks is not.
		self.run_command("mise", "run", "setup", check=False)
		for name, content in existing.items():
			self.assertEqual((hooks / name).read_text(), content)

	def test_installed_commit_msg_hook_adds_one_change_id(self) -> None:
		self.run_command("mise", "run", "setup")
		self.run_command("git", "commit", "--allow-empty", "-qm", "Subject")
		first = self.run_command("git", "log", "-1", "--format=%B").stdout
		self.assertRegex(first, r"(?m)^Change-Id: I[0-9a-f]{40}$")
		self.assertEqual(first.count("Change-Id:"), 1)
		self.run_command("git", "commit", "--amend", "--no-edit", "--allow-empty", "-q")
		self.assertEqual(self.run_command("git", "log", "-1", "--format=%B").stdout, first)


if __name__ == "__main__":
	unittest.main()
