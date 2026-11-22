# ADR 0002 — One workspace and independent local persistence

Status: accepted

Keep AppRouter as the navigation state owner, a single native workspace and SQLite history independent from view lifetime. Feature modules share the macOS SwiftPM target and use platform adapters. Preserve unsaved edit guards and existing runtime data paths. Consequence: the directory boundaries are logical, not module-enforced; changes to window layout require native validation.
