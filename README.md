# Dict Local AI

Local speech-to-text for macOS on Apple Silicon. Dictate into the focused editor, transcribe audio files, and record meeting audio for on-device transcription. The app uses SwiftUI, Core ML, Parakeet Ultra and Nemotron 3 diarization. The interface follows your macOS language preferences and supports English and Russian. If neither language is preferred, the app uses English.

## Features

- Dictation with configurable global hold-to-talk and hands-free shortcuts; paste into the active editor or copy to the clipboard when automatic insertion is unavailable.
- Local audio-file transcription (up to three hours) with optional speaker attribution, approximate timestamps and TXT/JSON export.
- Meeting transcription using macOS audio capture; incremental local history and export.
- A single native workspace, local SQLite history, and local diagnostic logging. No application telemetry service or cloud transcription.
- Models are installed separately from Hugging Face through Settings → Models. Inference is offline after installation.

## Build and install

Requirements: Apple Silicon Mac, macOS 15 or later, Xcode with Swift 6 (development/CI uses Swift 6.2), Python 3.11+ and [Task](https://taskfile.dev/). Install Task through Homebrew (`brew install go-task`) if needed, then run from a checked-out source tree:

```sh
task setup
task signing:setup
task check
task install
```

Follow `task signing:setup` to configure a persistent code-signing identity in Keychain. If a valid Apple Development identity already exists, you may use it instead (see [development](docs/development.md)). The installed development app is `~/Applications/Dict Local AI.app`. Open Settings → Models and explicitly install Parakeet Ultra and Nemotron 3 as needed. Grant microphone, Accessibility and system-audio permissions for the features that require them.

Use `task install` for both the first installation and subsequent updates; close the app first. It builds, installs and opens the app. Use `task run` to open it again without rebuilding. `task check` runs lint and the regular Python and Swift tests; desktop UI checks are separate (`task test:ui`). See the [command reference](docs/development.md#commands) for the full workflow. Use `task dmg` to create the styled local DMG in `dist/`. A local development signature is not a public distribution certificate. Public binaries require Developer ID signing and notarization; the default GitHub release workflow publishes source only. Do not install multiple copies on one Mac.

## Documentation

- [Architecture](ARCHITECTURE.md) and [design decisions](docs/adr/)
- [Development](docs/development.md), [testing](docs/testing.md), [releasing](docs/releasing.md)
- [Models and licenses](docs/models.md), [privacy](docs/privacy.md), [troubleshooting](docs/troubleshooting.md)
- [Design system](docs/design.md), [evaluation](benchmarks/README.md)
- [Contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md)

## License

The application's source code is MIT-licensed. Third-party code and model weights have their own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Model weights, certificates, recordings, transcripts and user logs are not included in this source distribution.
