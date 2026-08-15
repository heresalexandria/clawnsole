#!/usr/bin/env python3
"""Select the one release label attached to a pull request."""

from __future__ import annotations

import json
import os


RELEASE_LABELS = {"major", "minor", "patch"}
SKIP_LABEL = "no-release"


def main() -> None:
    labels = set(json.loads(os.environ.get("LABELS") or "[]"))
    selected = labels & (RELEASE_LABELS | {SKIP_LABEL})
    if len(selected) != 1:
        choices = ", ".join(sorted(RELEASE_LABELS | {SKIP_LABEL}))
        raise SystemExit(
            f"error: choose exactly one release label ({choices}); found "
            f"{', '.join(sorted(selected)) or 'none'}"
        )
    value = selected.pop()
    print("none" if value == SKIP_LABEL else value)


if __name__ == "__main__":
    main()
