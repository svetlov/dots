import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
INSPECTOR_PATH = (
    REPOSITORY_ROOT
    / "all"
    / "code-agents"
    / "skills"
    / "wrap-up-session"
    / "scripts"
    / "inspect_worktree.py"
)
CLEANUP_PATH = INSPECTOR_PATH.with_name("cleanup_worktree.py")
INSTALLER_PATH = REPOSITORY_ROOT / "install.py"

MODULE_SPEC = importlib.util.spec_from_file_location(
    "inspect_worktree",
    INSPECTOR_PATH,
)
inspect_worktree = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(inspect_worktree)
sys.modules["inspect_worktree"] = inspect_worktree

CLEANUP_MODULE_SPEC = importlib.util.spec_from_file_location(
    "cleanup_worktree",
    CLEANUP_PATH,
)
cleanup_worktree = importlib.util.module_from_spec(CLEANUP_MODULE_SPEC)
CLEANUP_MODULE_SPEC.loader.exec_module(cleanup_worktree)


def run_git(repository_path, *arguments):
    result = subprocess.run(
        ["git", *arguments],
        cwd=repository_path,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class TemporaryRepository:
    def __init__(self, root):
        self.root = Path(root) / "repository"
        self.worktree = Path(root) / "feature-worktree"

    def create(self):
        self.root.mkdir()
        run_git(self.root, "init", "-b", "main")
        run_git(self.root, "config", "user.name", "Skill Test")
        run_git(self.root, "config", "user.email", "skill-test@example.com")
        (self.root / "tracked.txt").write_text("initial\n", encoding="utf-8")
        run_git(self.root, "add", "tracked.txt")
        run_git(self.root, "commit", "-m", "initial")
        run_git(self.root, "branch", "feature")
        run_git(self.root, "worktree", "add", str(self.worktree), "feature")
        return self


class InspectorTests(unittest.TestCase):
    def test_clean_merged_linked_worktree_is_eligible_for_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()

            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertFalse(report["worktree"]["is_primary"])
        self.assertEqual(report["branch"]["name"], "feature")
        self.assertEqual(report["base"]["ref"], "main")
        self.assertEqual(report["status"]["change_count"], 0)
        self.assertEqual(report["integration"]["status"], "merged")
        self.assertTrue(report["cleanup"]["eligible"])
        self.assertEqual(report["cleanup"]["blockers"], [])

    def test_uncommitted_changes_are_reported_and_block_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            (repository.worktree / "tracked.txt").write_text(
                "changed\n",
                encoding="utf-8",
            )
            (repository.worktree / "untracked.txt").write_text(
                "new\n",
                encoding="utf-8",
            )

            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertEqual(report["status"]["change_count"], 2)
        self.assertEqual(
            {change["path"] for change in report["status"]["changes"]},
            {"tracked.txt", "untracked.txt"},
        )
        self.assertIn("uncommitted changes", report["cleanup"]["blockers"])
        self.assertFalse(report["cleanup"]["eligible"])

    def test_unmerged_commit_blocks_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            (repository.worktree / "tracked.txt").write_text(
                "feature\n",
                encoding="utf-8",
            )
            run_git(repository.worktree, "add", "tracked.txt")
            run_git(repository.worktree, "commit", "-m", "feature")

            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertEqual(report["commits"]["ahead_of_base"], 1)
        self.assertEqual(report["integration"]["status"], "unmerged")
        self.assertIn("branch is not merged", report["cleanup"]["blockers"])
        self.assertFalse(report["cleanup"]["eligible"])

    def test_in_progress_merge_is_reported_as_unfinished_work(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            (repository.root / "tracked.txt").write_text(
                "main\n",
                encoding="utf-8",
            )
            run_git(repository.root, "add", "tracked.txt")
            run_git(repository.root, "commit", "-m", "main change")
            (repository.worktree / "tracked.txt").write_text(
                "feature\n",
                encoding="utf-8",
            )
            run_git(repository.worktree, "add", "tracked.txt")
            run_git(repository.worktree, "commit", "-m", "feature change")

            merge_result = subprocess.run(
                ["git", "merge", "main"],
                cwd=repository.worktree,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(merge_result.returncode, 0)
            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertIn("merge", report["operations"])
        self.assertEqual(report["status"]["conflicted_count"], 1)
        self.assertIn(
            "Git operation in progress",
            report["cleanup"]["blockers"],
        )

    def test_patch_equivalent_branch_is_retained_for_explicit_review(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            (repository.root / "main-only.txt").write_text(
                "main\n",
                encoding="utf-8",
            )
            run_git(repository.root, "add", "main-only.txt")
            run_git(repository.root, "commit", "-m", "main change")
            (repository.worktree / "feature-only.txt").write_text(
                "feature\n",
                encoding="utf-8",
            )
            run_git(repository.worktree, "add", "feature-only.txt")
            run_git(repository.worktree, "commit", "-m", "feature change")
            feature_head = run_git(repository.worktree, "rev-parse", "HEAD")
            run_git(repository.root, "cherry-pick", feature_head)

            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertEqual(report["integration"]["status"], "patch-equivalent")
        self.assertIn(
            "branch is only patch-equivalent to base",
            report["cleanup"]["blockers"],
        )
        self.assertFalse(report["cleanup"]["eligible"])

    def test_primary_worktree_is_never_eligible_for_removal(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()

            report = inspect_worktree.inspect_repository(repository.root)

        self.assertTrue(report["worktree"]["is_primary"])
        self.assertIn("primary worktree", report["cleanup"]["blockers"])
        self.assertFalse(report["cleanup"]["eligible"])

    def test_workmux_base_configuration_takes_precedence(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            head = run_git(repository.root, "rev-parse", "main")
            run_git(
                repository.root,
                "update-ref",
                "refs/remotes/origin/main",
                head,
            )
            run_git(
                repository.root,
                "config",
                "branch.feature.workmux-base",
                "origin/main",
            )

            report = inspect_worktree.inspect_repository(repository.worktree)

        self.assertEqual(report["base"]["ref"], "origin/main")
        self.assertEqual(report["base"]["source"], "workmux")


class CleanupTests(unittest.TestCase):
    def test_cleanup_removes_only_the_validated_worktree_and_merged_branch(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            report = inspect_worktree.inspect_repository(repository.worktree)

            command_result = subprocess.run(
                [
                    sys.executable,
                    str(CLEANUP_PATH),
                    "--repository",
                    str(repository.worktree),
                    "--expected-worktree",
                    report["worktree"]["path"],
                    "--expected-branch",
                    report["branch"]["name"],
                    "--expected-head",
                    report["branch"]["head"],
                    "--expected-base",
                    report["base"]["ref"],
                ],
                cwd=repository.worktree,
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(command_result.stdout)

            self.assertTrue(result["worktree_removed"])
            self.assertTrue(result["branch_deleted"])
            self.assertFalse(repository.worktree.exists())
            branch_result = subprocess.run(
                ["git", "show-ref", "--verify", "refs/heads/feature"],
                cwd=repository.root,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(branch_result.returncode, 0)

    def test_cleanup_rejects_a_stale_head_without_changing_repository(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = TemporaryRepository(temporary_directory).create()
            report = inspect_worktree.inspect_repository(repository.worktree)

            with self.assertRaises(cleanup_worktree.CleanupError):
                cleanup_worktree.cleanup_repository(
                    repository_path=repository.worktree,
                    expected_worktree=report["worktree"]["path"],
                    expected_branch=report["branch"]["name"],
                    expected_head="0" * 40,
                    expected_base=report["base"]["ref"],
                )

            self.assertTrue(repository.worktree.exists())
            self.assertEqual(
                run_git(repository.root, "rev-parse", "feature"),
                report["branch"]["head"],
            )


class InstallerTests(unittest.TestCase):
    def test_code_agents_installer_links_skill_for_both_clients(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            home_directory = Path(temporary_directory) / "home"
            existing_skill = (
                home_directory / ".claude" / "skills" / "existing" / "SKILL.md"
            )
            existing_skill.parent.mkdir(parents=True)
            existing_skill.write_text("existing\n", encoding="utf-8")
            environment = os.environ.copy()
            environment["HOME"] = str(home_directory)

            subprocess.run(
                [
                    sys.executable,
                    str(INSTALLER_PATH),
                    "install",
                    "code-agents",
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )

            codex_skill = (
                home_directory
                / ".agents"
                / "skills"
                / "wrap-up-session"
            )
            claude_skill = (
                home_directory
                / ".claude"
                / "skills"
                / "wrap-up-session"
            )

            self.assertTrue(codex_skill.is_symlink())
            self.assertTrue(claude_skill.is_symlink())
            self.assertEqual(
                codex_skill.resolve(),
                (
                    REPOSITORY_ROOT
                    / "all"
                    / "code-agents"
                    / "skills"
                    / "wrap-up-session"
                ).resolve(),
            )
            self.assertEqual(codex_skill.resolve(), claude_skill.resolve())
            self.assertEqual(
                existing_skill.read_text(encoding="utf-8"),
                "existing\n",
            )


if __name__ == "__main__":
    unittest.main()
