#!/usr/bin/env python3
"""Prepare, commit, and push one release version for a merge or manual bump.

Merges may land on main faster than release runs complete, so this script
treats the push to main as the lock. When the push is rejected it re-reads
main and decides again; when a release commit that already contains this
merge has landed in the meantime, it stands down so the newer release ships
alone. The decision base for a merged pull request is the merge commit's
first parent -- main immediately before the merge -- so releases cut while
the pull request was open are never mistaken for a version the pull request
prepared itself.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import random
import subprocess
import sys
import time

import bump_version

COMMITTED_PATHS = (
    "electron/package.json",
    "electron/package-lock.json",
    "flutter/pubspec.yaml",
    "flutter/lib/core/app_version.dart",
    "docs/models/index.html",
)
GIT_IDENTITY = (
    "-c",
    "user.name=github-actions[bot]",
    "-c",
    "user.email=41898282+github-actions[bot]@users.noreply.github.com",
)


def run_git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=bump_version.ROOT,
        check=check,
        capture_output=True,
        text=True,
    )


def decide(kind: str, merge_ref: str | None) -> tuple[str, str, int]:
    """Return (outcome, version, build): bump, prepared, or superseded."""
    current, build = bump_version.versions()
    if merge_ref:
        if (current, build) != bump_version.versions_at(merge_ref):
            return ("superseded", current, build)
        base_version, base_build = bump_version.versions_at(f"{merge_ref}^")
        expected = bump_version.bumped(base_version, kind)
        if current == expected:
            if build != base_build + 1:
                raise SystemExit(
                    "error: the prepared version must advance the build number "
                    f"exactly once from {base_version}+{base_build}; "
                    f"found {current}+{build}"
                )
            return ("prepared", current, build)
        if current != base_version:
            raise SystemExit(
                f"error: expected {base_version} or prepared {expected} at this "
                f"pull request's merge; found {current}"
            )
    return ("bump", bump_version.bumped(current, kind), build + 1)


def advance_catalog(version: str, mobile_test: bool) -> None:
    script = Path(__file__).resolve().with_name("set_mobile_test_version.py")
    args = [
        sys.executable,
        str(script),
        version,
        "--index",
        str(bump_version.ROOT / "docs" / "models" / "index.html"),
    ]
    if mobile_test:
        args.append("--add-test")
    subprocess.run(args, check=True)


def emit_superseded() -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a") as stream:
            stream.write("superseded=true\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("major", "minor", "patch"))
    parser.add_argument(
        "--merge-ref", help="the merged pull request's merge commit on main"
    )
    parser.add_argument("--mobile-test", action="store_true")
    parser.add_argument("--attempts", type=int, default=5)
    args = parser.parse_args()

    for attempt in range(1, args.attempts + 1):
        outcome, version, build = decide(args.kind, args.merge_ref)
        if outcome == "superseded":
            emit_superseded()
            print(
                f"main already carries {version}+{build}, a release prepared "
                "after this merge; standing down"
            )
            return
        if outcome == "bump":
            bump_version.write_version_files(version, build)
        advance_catalog(version, args.mobile_test)
        run_git("add", "--", *COMMITTED_PATHS)
        if run_git("diff", "--cached", "--quiet", check=False).returncode == 0:
            bump_version.emit(version, build, changed=False)
            print(f"{version}+{build} (already prepared)")
            return
        run_git(*GIT_IDENTITY, "commit", "-m", f"Release v{version}")
        push = run_git("push", "origin", "HEAD:main", check=False)
        if push.returncode == 0:
            bump_version.emit(version, build, changed=outcome == "bump")
            print(f"{version}+{build}")
            return
        sys.stderr.write(push.stderr)
        print(f"the push was rejected (attempt {attempt}); re-reading main")
        run_git("fetch", "--no-tags", "origin", "main")
        run_git("reset", "--hard", "FETCH_HEAD")
        time.sleep(random.uniform(0.5, 1.5) * attempt)
    raise SystemExit(
        f"error: could not push the release version after {args.attempts} attempts"
    )


if __name__ == "__main__":
    main()
