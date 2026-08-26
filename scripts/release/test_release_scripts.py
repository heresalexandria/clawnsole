"""Tests for the release preparation scripts.

Each test runs against a throwaway Git repository (with a bare origin where
pushes matter) so racing-merge behavior is exercised for real: rejected
pushes, re-reads of main, and standing down behind a newer release.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bump_version
import prepare_release
import verify_prepared


PATCHED_PATHS = (
    "ROOT",
    "ELECTRON_PACKAGE",
    "ELECTRON_LOCK",
    "FLUTTER_PACKAGE",
    "FLUTTER_VERSION_SOURCE",
)


def git(root: Path, *args: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            "user.name=test",
            "-c",
            "user.email=test@example.invalid",
            *args,
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class ReleaseRepoTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.root = Path(self._temp.name) / "repo"
        (self.root / "electron").mkdir(parents=True)
        (self.root / "flutter" / "lib" / "core").mkdir(parents=True)
        (self.root / "docs" / "models").mkdir(parents=True)
        git(self.root, "init", "-b", "main")

        self._originals = {name: getattr(bump_version, name) for name in PATCHED_PATHS}
        bump_version.ROOT = self.root
        bump_version.ELECTRON_PACKAGE = self.root / "electron" / "package.json"
        bump_version.ELECTRON_LOCK = self.root / "electron" / "package-lock.json"
        bump_version.FLUTTER_PACKAGE = self.root / "flutter" / "pubspec.yaml"
        bump_version.FLUTTER_VERSION_SOURCE = (
            self.root / "flutter" / "lib" / "core" / "app_version.dart"
        )
        self.addCleanup(self._restore_paths)

        self.github_output = Path(self._temp.name) / "github_output"
        self._env = mock.patch.dict(
            os.environ, {"GITHUB_OUTPUT": str(self.github_output)}
        )
        self._env.start()
        self.addCleanup(self._env.stop)

        sleep = mock.patch.object(prepare_release.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

        # History: v0.44.0+106 released, then v0.44.1+107 released, then one
        # feature merge that does not touch versions -- the shape of the runs
        # that failed on 2026-08-26.
        self.write_tree("0.44.0", 106)
        self.commit_all("Release v0.44.0")
        self.write_tree("0.44.1", 107)
        self.commit_all("Release v0.44.1")
        (self.root / "feature.txt").write_text("merged change\n")
        self.merge_sha = self.commit_all("Keep generations alive (#125)")

    def _restore_paths(self) -> None:
        for name, value in self._originals.items():
            setattr(bump_version, name, value)

    def write_tree(self, version: str, build: int) -> None:
        bump_version.ELECTRON_PACKAGE.write_text(
            json.dumps({"name": "clawnsole", "version": version}, indent=2) + "\n"
        )
        bump_version.ELECTRON_LOCK.write_text(
            json.dumps(
                {
                    "name": "clawnsole",
                    "version": version,
                    "packages": {"": {"version": version}},
                },
                indent=2,
            )
            + "\n"
        )
        bump_version.FLUTTER_PACKAGE.write_text(
            f"name: clawnsole\nversion: {version}+{build}\n"
        )
        bump_version.FLUTTER_VERSION_SOURCE.write_text(
            f"const clawnsoleVersion = '{version}';\n"
        )
        (self.root / "docs" / "models" / "index.html").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "catalog_version": version,
                    "test_versions": [],
                },
                indent=2,
            )
            + "\n"
        )

    def commit_all(self, message: str) -> str:
        git(self.root, "add", "-A")
        git(self.root, "commit", "-m", message)
        return git(self.root, "rev-parse", "HEAD")

    def add_origin(self) -> Path:
        origin = Path(self._temp.name) / "origin.git"
        git(self.root, "init", "--bare", "-b", "main", str(origin))
        git(self.root, "remote", "add", "origin", str(origin))
        git(self.root, "push", "origin", "HEAD:main")
        return origin

    def advance_origin(self, build_commit) -> str:
        """Land a commit on origin/main that this checkout has not seen."""
        head = git(self.root, "rev-parse", "HEAD")
        sha = build_commit()
        git(self.root, "push", "origin", "HEAD:main")
        git(self.root, "reset", "--hard", head)
        return sha

    def run_prepare(self, *args: str) -> str:
        argv = ["prepare_release.py", *args]
        stdout = io.StringIO()
        with mock.patch.object(sys, "argv", argv):
            with contextlib.redirect_stdout(stdout):
                prepare_release.main()
        return stdout.getvalue()

    def outputs(self) -> dict[str, str]:
        if not self.github_output.exists():
            return {}
        values: dict[str, str] = {}
        for line in self.github_output.read_text().splitlines():
            key, _, value = line.partition("=")
            values[key] = value
        return values

    def catalog(self) -> dict:
        return json.loads((self.root / "docs" / "models" / "index.html").read_text())


class DecideTest(ReleaseRepoTest):
    def test_bump_when_merge_left_versions_alone(self) -> None:
        # Regression: v0.44.1+107 was already released before this merge. The
        # stale pull-request base snapshot used to make this look "already
        # prepared" and re-ship build 107; the merge parent base must bump.
        outcome = prepare_release.decide("patch", self.merge_sha)
        self.assertEqual(outcome, ("bump", "0.44.2", 108))

    def test_prepared_version_in_merge_is_preserved(self) -> None:
        self.write_tree("0.44.2", 108)
        prepared = self.commit_all("Advance iOS distribution build (#98)")
        outcome = prepare_release.decide("patch", prepared)
        self.assertEqual(outcome, ("prepared", "0.44.2", 108))

    def test_prepared_version_must_advance_build_once(self) -> None:
        self.write_tree("0.44.2", 110)
        prepared = self.commit_all("Bad prepared bump")
        with self.assertRaisesRegex(SystemExit, "exactly once"):
            prepare_release.decide("patch", prepared)

    def test_unexpected_version_change_fails(self) -> None:
        self.write_tree("0.47.0", 108)
        prepared = self.commit_all("Version from nowhere")
        with self.assertRaisesRegex(SystemExit, "expected 0.44.1 or prepared 0.44.2"):
            prepare_release.decide("patch", prepared)

    def test_release_landed_after_merge_is_superseded(self) -> None:
        self.write_tree("0.44.2", 108)
        self.commit_all("Release v0.44.2")
        outcome = prepare_release.decide("patch", self.merge_sha)
        self.assertEqual(outcome, ("superseded", "0.44.2", 108))

    def test_manual_bump_needs_no_merge_ref(self) -> None:
        outcome = prepare_release.decide("minor", None)
        self.assertEqual(outcome, ("bump", "0.45.0", 108))


class PrepareReleaseTest(ReleaseRepoTest):
    def test_bumps_and_pushes(self) -> None:
        origin = self.add_origin()
        self.run_prepare("patch", "--merge-ref", self.merge_sha)

        self.assertEqual(bump_version.versions(), ("0.44.2", 108))
        self.assertEqual(self.catalog()["catalog_version"], "0.44.2")
        self.assertEqual(
            git(origin, "log", "-1", "--format=%s"), "Release v0.44.2"
        )
        outputs = self.outputs()
        self.assertEqual(outputs["version"], "0.44.2")
        self.assertEqual(outputs["build"], "108")
        self.assertEqual(outputs["tag"], "v0.44.2")
        self.assertNotIn("superseded", outputs)

    def test_mobile_test_marks_catalog(self) -> None:
        self.add_origin()
        self.run_prepare("patch", "--merge-ref", self.merge_sha, "--mobile-test")
        self.assertIn("0.44.2", self.catalog()["test_versions"])

    def test_rejected_push_retries_on_new_main(self) -> None:
        origin = self.add_origin()

        def land_feature() -> str:
            (self.root / "raced.txt").write_text("raced merge\n")
            return self.commit_all("Fold card chrome (#128)")

        raced = self.advance_origin(land_feature)
        self.run_prepare("patch", "--merge-ref", self.merge_sha)

        # The release was recomputed on top of the raced merge, so one release
        # covers both merges and the build number still advances exactly once.
        self.assertEqual(git(origin, "log", "-1", "--format=%s"), "Release v0.44.2")
        self.assertEqual(bump_version.versions(), ("0.44.2", 108))
        self.assertTrue(
            git(origin, "merge-base", "--is-ancestor", raced, "main") == ""
        )

    def test_stands_down_when_race_loser_is_already_released(self) -> None:
        origin = self.add_origin()

        def land_release() -> str:
            self.write_tree("0.44.2", 108)
            return self.commit_all("Release v0.44.2")

        self.advance_origin(land_release)
        self.run_prepare("patch", "--merge-ref", self.merge_sha)

        self.assertEqual(self.outputs().get("superseded"), "true")
        self.assertNotIn("version", self.outputs())
        # Nothing new was pushed; the newer release still leads main.
        self.assertEqual(git(origin, "log", "-1", "--format=%s"), "Release v0.44.2")

    def test_prepared_merge_ships_catalog_commit_only(self) -> None:
        # A local distribution build prepares the version files but leaves the
        # catalog alone; the workflow still owns that advance.
        self.write_tree("0.44.2", 108)
        catalog_path = self.root / "docs" / "models" / "index.html"
        stale_catalog = self.catalog()
        stale_catalog["catalog_version"] = "0.44.1"
        catalog_path.write_text(json.dumps(stale_catalog, indent=2) + "\n")
        prepared = self.commit_all("Advance iOS distribution build (#98)")
        origin = self.add_origin()
        output = self.run_prepare("patch", "--merge-ref", prepared)

        self.assertEqual(bump_version.versions(), ("0.44.2", 108))
        self.assertEqual(self.catalog()["catalog_version"], "0.44.2")
        self.assertEqual(git(origin, "log", "-1", "--format=%s"), "Release v0.44.2")
        self.assertEqual(self.outputs()["changed"], "false")

        # A re-run finds nothing left to do and keeps the same release.
        head = git(self.root, "rev-parse", "HEAD")
        rerun = self.run_prepare("patch", "--merge-ref", prepared)
        self.assertIn("already prepared", rerun)
        self.assertEqual(git(self.root, "rev-parse", "HEAD"), head)

    def test_gives_up_after_exhausting_attempts(self) -> None:
        self.add_origin()

        real_run_git = prepare_release.run_git

        def failing_push(*args: str, check: bool = True):
            if args[:1] == ("push",) or "push" in args[:5]:
                completed = subprocess.CompletedProcess(args, 1, "", "rejected")
                return completed
            return real_run_git(*args, check=check)

        with mock.patch.object(prepare_release, "run_git", failing_push):
            with self.assertRaisesRegex(SystemExit, "could not push"):
                self.run_prepare("patch", "--merge-ref", self.merge_sha, "--attempts", "2")


class VerifyPreparedTest(ReleaseRepoTest):
    def run_verify(self, ref: str) -> str:
        stdout = io.StringIO()
        with mock.patch.object(sys, "argv", ["verify_prepared.py", ref]):
            with contextlib.redirect_stdout(stdout):
                verify_prepared.main()
        return stdout.getvalue()

    def test_newest_release_is_not_stale(self) -> None:
        output = self.run_verify("HEAD")
        self.assertEqual(self.outputs()["stale"], "false")
        self.assertIn("newest prepared release", output)

    def test_older_release_is_stale(self) -> None:
        checked_out = git(self.root, "rev-parse", "HEAD")
        self.write_tree("0.44.2", 108)
        self.commit_all("Release v0.44.2")
        newest = git(self.root, "rev-parse", "HEAD")
        git(self.root, "checkout", "--detach", checked_out)
        try:
            output = self.run_verify(newest)
        finally:
            git(self.root, "checkout", "main")
        self.assertEqual(self.outputs()["stale"], "true")
        self.assertIn("supersedes", output)


class BumpVersionTest(ReleaseRepoTest):
    def test_write_version_files_updates_every_target(self) -> None:
        bump_version.write_version_files("0.45.0", 109)
        self.assertEqual(bump_version.versions(), ("0.45.0", 109))
        lock = json.loads(bump_version.ELECTRON_LOCK.read_text())
        self.assertEqual(lock["packages"][""]["version"], "0.45.0")
        self.assertIn(
            "const clawnsoleVersion = '0.45.0';",
            bump_version.FLUTTER_VERSION_SOURCE.read_text(),
        )

    def test_mismatched_targets_fail(self) -> None:
        bump_version.FLUTTER_PACKAGE.write_text("name: clawnsole\nversion: 0.9.9+1\n")
        with self.assertRaisesRegex(SystemExit, "Electron is 0.44.1"):
            bump_version.versions()


if __name__ == "__main__":
    unittest.main()
