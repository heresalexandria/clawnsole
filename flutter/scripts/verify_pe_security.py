#!/usr/bin/env python3

"""Reject Windows executables that lack basic exploit mitigations."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


HIGH_ENTROPY_VA = 0x0020
DYNAMIC_BASE = 0x0040
NX_COMPAT = 0x0100
REQUIRED = HIGH_ENTROPY_VA | DYNAMIC_BASE | NX_COMPAT


def characteristics(path: Path) -> int:
    data = path.read_bytes()
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError("not a PE file")
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    optional_offset = pe_offset + 4 + 20
    if data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise ValueError("invalid PE signature")
    magic = struct.unpack_from("<H", data, optional_offset)[0]
    if magic not in (0x10B, 0x20B):
        raise ValueError("unsupported PE optional header")
    return struct.unpack_from("<H", data, optional_offset + 0x46)[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.paths:
        try:
            flags = characteristics(path)
        except (OSError, ValueError, struct.error) as error:
            print(f"{path}: {error}")
            failed = True
            continue
        missing = REQUIRED & ~flags
        if missing:
            print(
                f"{path}: missing PE mitigations 0x{missing:04x} "
                f"(DllCharacteristics=0x{flags:04x})"
            )
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
