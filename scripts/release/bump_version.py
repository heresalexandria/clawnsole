#!/usr/bin/env python3
"""Bump Clawnsole's Electron and Flutter versions together."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]
ELECTRON_PACKAGE = ROOT / "electron" / "package.json"
ELECTRON_LOCK = ROOT / "electron" / "package-lock.json"
FLUTTER_PACKAGE = ROOT / "flutter" / "pubspec.yaml"
FLUTTER_VERSION_SOURCE = ROOT / "flutter" / "lib" / "core" / "app_version.dart"
VERSION_PATTERN = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.MULTILINE)
SOURCE_VERSION_PATTERN = re.compile(r"const clawnsoleVersion = '(\d+)\.(\d+)\.(\d+)';")


def parsed_versions(package_source: str, flutter_source: str) -> tuple[str, int]:
    package = json.loads(package_source)
    source = flutter_source
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


def versions() -> tuple[str, int]:
    return parsed_versions(ELECTRON_PACKAGE.read_text(), FLUTTER_PACKAGE.read_text())


def versions_at(ref: str) -> tuple[str, int]:
    def read(path: Path) -> str:
        relative = path.relative_to(ROOT).as_posix()
        result = subprocess.run(
            ["git", "show", f"{ref}:{relative}"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout

    return parsed_versions(read(ELECTRON_PACKAGE), read(FLUTTER_PACKAGE))


def bumped(version: str, kind: str) -> str:
    parts = [int(value) for value in version.split(".")]
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    parts[index] += 1
    for trailing in range(index + 1, 3):
        parts[trailing] = 0
    return ".".join(str(value) for value in parts)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def emit(version: str, build: int, *, changed: bool | None = None) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a") as stream:
            stream.write(f"version={version}\n")
            stream.write(f"tag=v{version}\n")
            stream.write(f"build={build}\n")
            if changed is not None:
                stream.write(f"changed={'true' if changed else 'false'}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", nargs="?", choices=("major", "minor", "patch"))
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--current", action="store_true")
    parser.add_argument("--show", action="store_true")
    parser.add_argument(
        "--base-ref",
        help="treat an exact bump already prepared relative to this Git ref as current",
    )
    args = parser.parse_args()
    if args.build_only and (args.kind or args.current or args.show):
        parser.error("--build-only cannot be combined with another version action")
    if args.base_ref and not args.kind:
        parser.error("--base-ref requires a version bump kind")

    current, build = versions()
    if args.show:
        print(current)
        return
    if args.current:
        emit(current, build)
        print(f"{current}+{build}")
        return
    if args.build_only:
        source = FLUTTER_PACKAGE.read_text()
        source = VERSION_PATTERN.sub(
            f"version: {current}+{build + 1}", source, count=1
        )
        FLUTTER_PACKAGE.write_text(source)
        emit(current, build + 1)
        print(f"{current}+{build + 1}")
        return
    if not args.kind:
        parser.error("a bump kind is required")

    if args.base_ref:
        base_version, base_build = versions_at(args.base_ref)
        expected = bumped(base_version, args.kind)
        if current == expected:
            if build != base_build + 1:
                raise SystemExit(
                    "error: the prepared version must advance the build number exactly once "
                    f"from {base_version}+{base_build}; found {current}+{build}"
                )
            emit(current, build, changed=False)
            print(f"{current}+{build} (already prepared)")
            return
        if current != base_version:
            raise SystemExit(
                f"error: expected {base_version} or prepared {expected} relative to "
                f"{args.base_ref}; found {current}"
            )

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

    dart_source = FLUTTER_VERSION_SOURCE.read_text()
    if not SOURCE_VERSION_PATTERN.search(dart_source):
        raise SystemExit("error: lib/core/app_version.dart has no version constant")
    dart_source = SOURCE_VERSION_PATTERN.sub(
        f"const clawnsoleVersion = '{version}';", dart_source, count=1
    )
    FLUTTER_VERSION_SOURCE.write_text(dart_source)

    emit(version, build + 1, changed=True)
    print(f"{version}+{build + 1}")


if __name__ == "__main__":
    main()
