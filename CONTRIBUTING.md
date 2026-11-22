# Contributing

Use focused changes on a branch. Keep SwiftPM target dependencies explicit; prefer existing feature and platform boundaries. Do not introduce a second router, a second ASR engine, hidden model downloads or cloud processing as incidental changes.

Run `task setup`, `task check` and applicable native acceptance scenarios before opening a PR. Linux can run `swift test` for DictCore and `python3 -m unittest discover -s scripts/tests`. Explain risks, verification gaps and rollback. Source-contract tests are not substitutes for native UI or input integration tests.

Use synthetic test inputs. Never include real recordings, transcripts, logs, credentials, signing material, or private dataset hashes. Keep the public tree gate and Gitleaks clean. Report security issues privately as described in SECURITY.md. Contributions are licensed under MIT, except where existing third-party terms apply.
