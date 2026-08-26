#!/usr/bin/env python3
"""Confirm the checked-out prepared release still carries main's newest version.

A trusted release build must only ship main's newest prepared version. When a
newer release has been prepared -- because merges raced, or because an old run
was re-run -- this emits ``stale=true`` so the workflow stands down instead of
rebuilding a bundle version App Store Connect has already moved past.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from bump_version import versions, versions_at


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ref", help="the Git ref holding main's newest state")
    args = parser.parse_args()

    version, build = versions()
    newest_version, newest_build = versions_at(args.ref)
    stale = (version, build) != (newest_version, newest_build)

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a") as stream:
            stream.write(f"stale={'true' if stale else 'false'}\n")

    if stale:
        print(
            f"notice: this run prepared {version}+{build}, but main now carries "
            f"{newest_version}+{newest_build}; a newer release supersedes it"
        )
    else:
        print(f"{version}+{build} is main's newest prepared release")


if __name__ == "__main__":
    main()
