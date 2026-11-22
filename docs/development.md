# Development

Use an Apple Silicon Mac with full Xcode (Swift 6.2 recommended), Python 3.11+, Git and Task. `brew install go-task`; `task setup` installs/checks development utilities using Homebrew bottle verification. Tool versions are printed during setup; Homebrew tool versions track the installed formulae, not an immutable custom toolchain lock. Swift dependencies are pinned separately in Package.swift and Package.resolved.

```sh
task check        # lint, contracts and all Swift test suites; compiles debug code
task signing:setup
task install      # build release, install or update, then open; quit running copies first
task run          # open the installed app without rebuilding
```

## Commands

Run `task` to list available commands. Each operation has one command; there are
no `open`, `update` or `eval:wer:test` aliases.

| Command | Purpose |
| --- | --- |
| `task setup` | Install or check development tools. |
| `task signing:setup` | Configure a persistent signing identity, usually once. |
| `task format` | Apply Swift formatting to source and tests. |
| `task lint` | Check Swift formatting, SwiftLint, ShellCheck and shell syntax. |
| `task test` | Run source and packaging contracts, then all four Swift test suites. |
| `task check` | Run `lint`, then `test`; stop if either fails. |
| `task build` | Build the release app in `dist/`, package resources, check portability and sign it. |
| `task install` | Run the release build, install or replace the existing app, and open it. |
| `task run` | Open the installed app without building or installing. |
| `task package` | Build the app and create a release ZIP and checksums. |
| `task dmg` | Build the app and create a ZIP, DMG and checksums. |

`check` includes debug compilation through the Swift tests. It does not run a
second debug build, build a release app, sign, install or open the app. Use
`task check && task install` to check changes and try the release app locally.
`install` already opens the app, so a subsequent `run` is unnecessary.

Additional checks are explicit: `test:contracts` runs only source and packaging
contracts (including UI tokens); `test:ui` runs `ui:smoke`, then `ui:geometry`
against the installed app; `test:localization` builds and checks a DMG. UI and
DMG checks are separate from ordinary `test` and `check`; see [testing.md](testing.md).

Maintenance commands remain separate: `clean`; `reinstall` and `uninstall`,
including their `:purge` variants; `permissions:doctor`, `permissions:reset`, `logs:open`
and `logs:tail`; `hooks:install` for commit hooks; `release:notarize` for public
distribution. The `eval:benchmark`, `eval:clips`, `eval:wer` and `eval:diarization`
commands work with supplied evaluation recordings and references, rather than
running the regular test suite.

For local signing, use a valid persistent Code Signing identity from Keychain. `task signing:setup` explains the self-signed local option. The first successful build pins the identity under `~/.config/dict-local-ai/signing-identity`. Use `DICT_CODESIGN_IDENTITY` only to choose the initial identity if multiple identities exist. Do not delete the pin or private key to bypass a failed update. Local development signing is not Developer ID distribution signing.

On Linux (core only):

```sh
swift test
python3 -m unittest discover -s scripts/tests
bash scripts/development/verify-system-audio.sh
python3 scripts/development/verify-ui-tokens.py
```

Use `task clean` to remove build outputs, not runtime data. `task uninstall:purge` is an explicit destructive operation requiring confirmation; ordinary clean/install does not erase history. `task permissions:doctor` is read-only. See troubleshooting.

Packaging uses only hash-pinned Python wheels listed in `scripts/release/requirements.txt`. Linux SwiftPM excludes the macOS dependency and may remove the macOS lockfile on resolution; restore `Package.resolved` from Git after a Linux-only test run. Regenerate and validate the lock on macOS before publishing.

## Commit checks

Run `task hooks:install` from a Git checkout on macOS. It uses Homebrew to
install the hook tools. The hook checks only files staged for the commit. It
uses Swift format and SwiftLint for Swift, ShellCheck for Bash, and Biome 2.6+
for JSON, JSONC, YAML and Markdown. It also checks Python and plist syntax
and runs actionlint on changed GitHub workflows.

If a check fails, fix the file and stage it again. Format one file with
`swift format format --in-place PATH` or `biome format --write PATH`.
The hook leaves the Git index and working files intact. Run `task check`
for lint and all regular automated tests, including debug compilation.

## Localization

UI strings live in `Resources/App/{en,ru}.lproj`. Use stable keys for new text,
whole sentences for translation, and `Localizable.stringsdict` for plural forms.
Use `InfoPlist.strings` for permission prompts. The app uses macOS language
preferences, including the per-app override in Language & Region.

Keep recording content, names entered by users, JSON keys, and log event
IDs independent of the interface language. New recording titles and TXT report
labels follow the app language. The evaluator reads generated labels in
English and Russian. Saved recording titles are preserved.

`task test:contracts` checks both resource sets and their format arguments.
`task test:localization` uses an isolated build directory to create and mount a
DMG on macOS. It runs the app executable in check mode with several language
lists, including unsupported-language fallback. It checks language selection,
text, plural forms, and both permission descriptions without recording audio,
changing system preferences, or asking for permission. Run `task test:ui` on
a Mac with Accessibility and Automation access to check navigation and window
geometry together. `task ui:smoke` and `task ui:geometry` remain available for
running either scenario individually.
