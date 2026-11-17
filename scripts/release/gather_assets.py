#!/usr/bin/env python3
"""Gather a complete desktop release, stable download aliases, and checksums."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import shutil


# macOS ZIP is the updater payload; the other formats are user downloads.
ASSET_SUFFIXES = (
    "mac-arm64.dmg",
    "mac-arm64.zip",
    "windows-x64.zip",
    "linux-x64.deb",
    "linux-x64.tar.gz",
    "linux-arm64.deb",
    "linux-arm64.tar.gz",
)
DOWNLOAD_SUFFIXES = tuple(s for s in ASSET_SUFFIXES if s != "mac-arm64.zip")


def gather(version: str, incoming: Path, output: Path) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a release version in X.Y.Z form")

    # Validate the entire set before writing anything. A missing architecture,
    # duplicate artifact, or empty package must never become a partial release.
    sources = {}
    for suffix in ASSET_SUFFIXES:
        name = f"Clawnsole-{version}-{suffix}"
        matches = [p for p in incoming.rglob(name) if p.is_file()]
        if len(matches) != 1 or matches[0].stat().st_size == 0:
            raise ValueError(f"Expected exactly one nonempty release asset: {name}")
        sources[suffix] = matches[0]

    output.mkdir(parents=True, exist_ok=False)
    for suffix, source in sources.items():
        shutil.copyfile(source, output / source.name)
        if suffix in DOWNLOAD_SUFFIXES:
            shutil.copyfile(source, output / f"Clawnsole-{suffix}")

    lines = []
    for asset in sorted(output.iterdir()):
        digest = hashlib.sha256()
        with asset.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        lines.append(f"{digest.hexdigest()}  {asset.name}\n")
    (output / "SHA256SUMS.txt").write_text("".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--incoming", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    gather(args.version, args.incoming, args.output)


if __name__ == "__main__":
    main()
