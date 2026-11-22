#!/usr/bin/env python3
"""Reject development-only paths in the distributable app."""

import mmap
import pathlib
import plistlib
import sys


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]


def check_plist(value) -> None:
    if isinstance(value, str) and value.startswith(("/Users/", "/home/")):
        raise ValueError("Info.plist includes a developer-local path")
    if isinstance(value, dict):
        for item in value.values():
            check_plist(item)
    elif isinstance(value, list):
        for item in value:
            check_plist(item)


def check(bundle: pathlib.Path, checkout: pathlib.Path = PROJECT_ROOT) -> None:
    info_path = bundle / "Contents" / "Info.plist"
    with info_path.open("rb") as file:
        info = plistlib.load(file)
    if "DictProjectRoot" in info:
        raise ValueError("DictProjectRoot must not be embedded in the app bundle")
    if info.get("CFBundleIdentifier") != "app.dictlocalai.desktop":
        raise ValueError("Unexpected bundle identifier")
    check_plist(info)
    checkout_paths = {
        str(checkout.absolute()).encode() + b"/",
        str(checkout.resolve()).encode() + b"/",
    }
    for path in bundle.rglob("*"):
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            continue
        with path.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
            if any(data.find(checkout_path) >= 0 for checkout_path in checkout_paths):
                raise ValueError(f"Build checkout path found in {path.relative_to(bundle)}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify-portable-bundle.py '/path/to/Dict Local AI.app'")
    try:
        check(pathlib.Path(sys.argv[1]))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"ERROR: non-portable app bundle: {error}")
    print("PASS: app bundle contains no checkout paths or developer-only Info.plist settings")
