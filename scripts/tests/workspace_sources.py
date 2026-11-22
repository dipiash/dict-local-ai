from pathlib import Path

APP = Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"
FILES = (
    "Features/Dictation/RecordingView.swift",
    "Features/Dictation/DictationWorkspaceView.swift",
    "App/WorkspaceView.swift",
    "Features/History/HistoryView.swift",
)

def workspace_source():
    return "\n".join((APP / name).read_text(encoding="utf-8") for name in FILES)
