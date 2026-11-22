#!/usr/bin/env python3
"""Fail closed on prohibited tracked artifact paths. Run inside the public Git repo."""
import pathlib
import re
import unicodedata
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
raw = subprocess.check_output(["git", "ls-files", "--stage", "-z"], cwd=ROOT)
entries = [entry.split(b"\t", 1) for entry in raw.split(b"\0") if entry]
blocked_dirs = {".build", ".swiftpm", ".tools", ".private", "local-data", "logs", "dist",
                "__pycache__", ".idea", ".vscode", "fixtures", "deriveddata",
                "xcuserdata", "transcripts", "recordings", "review-kit", ".dev-certs", ".pytest_cache", ".ruff_cache"}
blocked_suffixes = {".pyc", ".pyo", ".dmg", ".app", ".zip", ".key", ".p8", ".p12",
                    ".pfx", ".pem", ".cer", ".log", ".wav", ".mp3", ".m4a", ".aac",
                    ".flac", ".aiff", ".caf", ".sqlite", ".sqlite3", ".db", ".mlmodel",
                    ".mlpackage", ".mlmodelc", ".safetensors", ".pt", ".pth", ".onnx",
                    ".gguf", ".nemo", ".mobileprovision", ".provisionprofile", ".xcarchive", ".dsym", ".tar.gz"}
allowed_benchmarks = {"benchmarks/readme.md", "benchmarks/references.json"}
private_review = re.compile(r"(?:^|[-_. ])(?:handoff|manifest|private[-_. ]review(?:[-_. ]kit)?|independent[-_. ]review|"
                            r"public[-_. ]checklist|public[-_. ]preparation[-_. ]prompt)(?:[-_. (]|$)")
errors = []
seen = set()
for metadata, raw_path in entries:
    original = raw_path.decode()
    name = unicodedata.normalize("NFC", original).casefold()
    path = pathlib.PurePosixPath(name)
    mode, _, stage = metadata.split()
    if (mode not in (b"100644", b"100755") or stage != b"0" or name in seen
            or blocked_dirs.intersection(path.parts)
            or private_review.search(path.name)
            or any(part.startswith(".venv") or part.lower().endswith(tuple(blocked_suffixes))
                   for part in path.parts)
            or path.name.startswith('.env') and path.name != '.env.example'
            or path.name.endswith(('-diarization-audit.json', '.sample.txt', '-wal', '-shm'))
            or path.name.startswith('session-') and path.name.endswith('.json')
            or path.name in {'weight.bin', '.ds_store'}
            or path.parts[0] == 'benchmarks' and name not in allowed_benchmarks):
        errors.append(original)
    seen.add(name)
if errors:
    print('Prohibited tracked paths:', *errors, sep='\n', file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(entries)} tracked paths passed the public-tree gate')
