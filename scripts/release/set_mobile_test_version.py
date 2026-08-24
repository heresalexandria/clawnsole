#!/usr/bin/env python3
"""Advance /models and optionally change one mobile test version."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INDEX = ROOT / "docs" / "models" / "index.html"
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--add-test", action="store_true")
    action.add_argument("--remove-test", action="store_true")
    parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    args = parser.parse_args()

    if not VERSION_PATTERN.fullmatch(args.version):
        raise SystemExit("error: version must be an X.Y.Z semantic app version")

    value = json.loads(args.index.read_text())
    if value.get("schema_version") != 1:
        raise SystemExit("error: the model index schema is unsupported")
    versions = value.get("test_versions")
    if not isinstance(versions, list) or not all(
        isinstance(version, str) and VERSION_PATTERN.fullmatch(version)
        for version in versions
    ):
        raise SystemExit("error: test_versions must be a list of X.Y.Z versions")
    if len(versions) != len(set(versions)):
        raise SystemExit("error: test_versions contains duplicates")

    if not args.remove_test:
        value["catalog_version"] = args.version

    if args.remove_test:
        value["test_versions"] = [
            version for version in versions if version != args.version
        ]
    elif args.add_test and args.version not in versions:
        value["test_versions"] = [*versions, args.version]

    args.index.write_text(json.dumps(value, indent=2) + "\n")


if __name__ == "__main__":
    main()
