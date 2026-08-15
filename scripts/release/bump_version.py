#!/usr/bin/env python3
"""Bump Clawnsole's Electron and Flutter versions together."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
ELECTRON_PACKAGE = ROOT / "electron" / "package.json"
ELECTRON_LOCK = ROOT / "electron" / "package-lock.json"
FLUTTER_PACKAGE = ROOT / "flutter" / "pubspec.yaml"
VERSION_PATTERN = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.MULTILINE)


def versions() -> tuple[str, int]:
    package = json.loads(ELECTRON_PACKAGE.read_text())
    source = FLUTTER_PACKAGE.read_text()
    match = VERSION_PATTERN.search(source)
    if not match:
        raise SystemExit("error: flutter/pubspec.yaml has no semantic version and build number")
    flutter_version = ".".join(match.groups()[:3])
    electron_version = str(package["version"])
    if electron_version != flutter_version:
        raise SystemExit(
            f"error: Electron is {electron_version}, but Flutter is {flutter_version}"
        )
    return electron_version, int(match.group(4))


def bumped(version: str, kind: str) -> str:
    parts = [int(value) for value in version.split(".")]
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    parts[index] += 1
    for trailing in range(index + 1, 3):
        parts[trailing] = 0
    return ".".join(str(value) for value in parts)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def emit(version: str, build: int) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a") as stream:
            stream.write(f"version={version}\n")
            stream.write(f"tag=v{version}\n")
            stream.write(f"build={build}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", nargs="?", choices=("major", "minor", "patch"))
    parser.add_argument("--current", action="store_true")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()
    current, build = versions()
    if args.show:
        print(current)
        return
    if args.current:
        emit(current, build)
        print(f"{current}+{build}")
        return
    if not args.kind:
        parser.error("a bump kind is required")

    version = bumped(current, args.kind)
    package = json.loads(ELECTRON_PACKAGE.read_text())
    package["version"] = version
    write_json(ELECTRON_PACKAGE, package)

    lock = json.loads(ELECTRON_LOCK.read_text())
    lock["version"] = version
    if "" in lock.get("packages", {}):
        lock["packages"][""]["version"] = version
    write_json(ELECTRON_LOCK, lock)

    source = FLUTTER_PACKAGE.read_text()
    source = VERSION_PATTERN.sub(f"version: {version}+{build + 1}", source, count=1)
    FLUTTER_PACKAGE.write_text(source)

    emit(version, build + 1)
    print(f"{version}+{build + 1}")


if __name__ == "__main__":
    main()
