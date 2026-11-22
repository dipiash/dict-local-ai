# Testing

Run `task check` on an Apple Silicon Mac. `DictCoreTests` covers transcript and recognition rules. `DictApplicationTests` covers dictation delivery, file and meeting workflows, and model setup. `DictStorageTests` exercises the SQLite adapter. `DictMacTests` covers native API contracts and adapters; Python tests guard packaging, paths and source-level layout contracts. On Linux the manifest excludes the macOS executable and native tests. Optional DER evaluation tests require `pyannote.metrics`; record any skips.

| Command | Included checks |
| --- | --- |
| `task test:contracts` | System audio contract, UI tokens and all Python tests in `scripts/tests`. |
| `task test` | `test:contracts`, then compilation and execution of all four Swift test suites. |
| `task check` | `lint`, then `test`. Debug compilation is already included in `test`. |
| `task test:ui` | `ui:smoke`, then `ui:geometry`, using the installed app and desktop. |
| `task test:localization` | Build a DMG and check language selection and localized resources at runtime. |

Stages run sequentially and stop on failure. Individual tests can be skipped
when optional requirements are unavailable; check the reported skip count.
`test` and `check` do not run the desktop UI or localization DMG scenarios, build
a release app, or evaluate recognition quality on real recordings. Run the
applicable scenarios below before release.

## Continuous integration

The Check workflow runs on pushes, pull requests and manual dispatches. Its
independent Linux static-checks job runs actionlint against GitHub workflows,
Biome formatting checks against tracked JSON, JSONC, YAML and Markdown files
(excluding third-party license texts), and Python syntax checks against every
tracked Python file. Biome and actionlint versions and download SHA-256 hashes
are pinned in the workflow. Formatting checks do not rewrite files.

The other jobs scan files and Git history for secrets, validate the tracked
source tree, run portable tests on Linux, and run `task check` plus
`task test:localization` on macOS ARM64. Desktop UI tests and real recording
acceptance scenarios remain separate. The source-release workflow requires
all Check jobs to pass before it creates a draft release.

## Native acceptance (release gate)

- Clean source checkout; resolve FluidAudio, compare lock pin, build, test and lint on ARM64. Install both models from clean cache and run inference. Reopen offline with the current verified cache; no background downloads.
- Check all six sections, Settings subpages, Cmd+Tab, Dock/tray, close/reopen, history with long transcripts, save/discard/cancel and quit guards. `task test:ui` runs the navigation and window geometry checks together; both remain individually available as `ui:smoke` and `ui:geometry`.
- Hold-to-talk and hands-free dictation: bb/Monaco, browser ChatGPT, own editor, app/field switch while recording, missing target fallback, secure field. No duplicated text or lost result.
- File transcription with/without speakers, mixed language and timestamps; test long input, cancel and partial output. Test meeting capture using only system audio, including when microphone permission is denied, exports and local retention.
- Check local permissions and identity before/after updating with `task install`. Verify DMG contents, original icon and Applications link, no Finder window during build; open manually and inspect layout. Test distribution separately on a clean Mac.

Never use real private recordings as public fixtures. Tests passing in CI cannot alone certify macOS interactive behavior or model quality.
