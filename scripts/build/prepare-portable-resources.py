#!/usr/bin/env python3
"""Override SwiftPM's generated FluidAudio accessor for the packaged application."""

import hashlib
import json
import pathlib
import sys


def prepare(binary_dir: pathlib.Path, output_dir: pathlib.Path) -> pathlib.Path:
    source = pathlib.Path(__file__).with_name("portable-resource-bundle.swift").resolve()
    generated = binary_dir.resolve() / "FluidAudio.build/DerivedSources/resource_bundle_accessor.swift"
    content = json.dumps(
        {
            "version": 0,
            "use-external-names": False,
            "roots": [
                {"type": "file", "name": str(generated), "external-contents": str(source)}
            ],
        },
        indent=2,
    ) + "\n"
    # Template edits must change SwiftPM's compiler arguments to invalidate its cache.
    digest = hashlib.sha256(content.encode() + source.read_bytes()).hexdigest()
    overlay = output_dir.resolve() / f"{digest}.json"
    overlay.parent.mkdir(parents=True, exist_ok=True)
    if not overlay.exists():
        overlay.write_text(content, encoding="utf-8")
    return overlay


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-portable-resources.py BINARY_DIRECTORY OUTPUT_DIRECTORY")
    print(prepare(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
