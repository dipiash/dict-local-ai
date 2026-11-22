# Privacy

Speech inference and diarization run locally. Model installation contacts Hugging Face; source builds fetch dependencies and build tooling. There is no application telemetry service. Diagnostic events are written locally and may include metadata, errors and operational details. They are not designed for public upload without review.

Runtime data lives under `~/Library/Application Support/Dict Local AI/` (models, receipts and SQLite history), `~/Library/Logs/Dict Local AI/` (local logs), and macOS preferences. Audio is processed in memory by the app, not intentionally retained as an audio recording. Original imported audio files and explicitly exported transcripts are user-controlled. History retention defaults to seven days; inspect Storage settings to change history behavior. Logs are separate from history. Clipboard fallback places recognized text in the system pasteboard; other authorized apps or system clipboard features may access it.

Permissions: microphone for dictation, Accessibility for system-wide shortcuts and insertion, system audio for meeting capture. No screen image capture is required. macOS controls grants. Deleting history is not a secure disk-erasure guarantee. Ordinary updating does not reset permissions or delete runtime data. Only use the explicit purge flow when you intend to erase app-owned data.
