#!/usr/bin/env python3
"""Check that macOS views use shared layout values."""
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"
FILES = ["App/WorkspaceView.swift", "Features/Dictation/RecordingView.swift",
         "Features/Dictation/DictationWorkspaceView.swift", "Features/History/HistoryView.swift", "Features/Meetings/MeetingView.swift", "Features/Files/FileTranscriptionView.swift",
         "Features/Settings/ModelsView.swift", "Shared/Components/TranscriptResultView.swift", "Shared/DesignSystem/AppStyle.swift"]
PATTERNS = [
    re.compile(r"\.padding\((?:\.horizontal, |\.vertical, )?\d+\)"),
    re.compile(r"\bspacing:\s*\d+\b"),
    re.compile(r"\bcornerRadius:\s*\d+\b"),
    re.compile(r"\.font\(\.system\(size:\s*\d+"),
    re.compile(r"\bColor\(red:\s*"),
]
violations = []
for name in FILES:
    source = (ROOT / name).read_text()
    for n, line in enumerate(source.splitlines(), 1):
        if any(p.search(line) for p in PATTERNS):
            violations.append(f"{name}:{n}: {line.strip()}")
if violations:
    print("UI design token violations:", *violations, sep="\n")
    sys.exit(1)
print(f"PASS: UI tokens validated ({len(FILES)} macOS view files)")
