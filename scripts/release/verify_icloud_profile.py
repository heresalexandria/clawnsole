#!/usr/bin/env python3
"""Check that a decoded distribution profile grants the app's iCloud access.

Apple profile values and certificates stay local. CI decodes the signed profile
with `security cms` before invoking this check; no network or account mutation is
performed here.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import plistlib
import sys


ICLOUD_KEYS = (
    "com.apple.developer.icloud-services",
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.ubiquity-container-identifiers",
)


def validate(profile: dict, requested: dict) -> None:
    granted = profile.get("Entitlements")
    if not isinstance(granted, dict):
        raise ValueError("The provisioning profile has no valid entitlement dictionary.")
    for key in ICLOUD_KEYS:
        required = requested.get(key)
        if not isinstance(required, list) or not required or not all(
            isinstance(value, str) and value for value in required
        ):
            raise ValueError(f"Runner.entitlements must declare a nonempty {key} array.")
        values = granted.get(key)
        # Apple-issued profiles can authorize all iCloud services with a scalar
        # wildcard: https://developer.apple.com/library/archive/technotes/tn2415/
        # Keep container grants exact: a wildcard service
        # grant must not hide a missing/wrong product container association.
        if key == "com.apple.developer.icloud-services" and values == "*":
            continue
        if not isinstance(values, list) or not all(
            isinstance(value, str) for value in values
        ) or not set(required).issubset(values):
            raise ValueError(
                f"IOS_PROVISIONING_PROFILE does not cover {key}. "
                "Regenerate the App Store profile after enabling iCloud Documents "
                "and update the app-store-connect environment's profile secret."
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile-plist", type=Path, required=True)
    parser.add_argument("--entitlements", type=Path, required=True)
    args = parser.parse_args()
    try:
        with args.profile_plist.open("rb") as stream:
            profile = plistlib.load(stream)
        with args.entitlements.open("rb") as stream:
            requested = plistlib.load(stream)
        if not isinstance(profile, dict) or not isinstance(requested, dict):
            raise ValueError("Expected profile and app entitlement dictionaries.")
        validate(profile, requested)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        # Do not print parsed profile contents or certificate data.
        message = str(error) if isinstance(error, ValueError) else "Unable to read profile or app entitlements."
        print(f"::error::{message}", file=sys.stderr)
        return 1
    print("App Store profile covers the app's iCloud Documents services and containers.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
