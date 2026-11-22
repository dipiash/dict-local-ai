#!/bin/bash
set -euo pipefail
repository="${DICT_REPOSITORY:-}"
version="${DICT_VERSION:-latest}"
team_id="${DICT_RELEASE_TEAM_ID:-}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || fail 'Dict Local AI requires macOS.'
[[ $(uname -m) == arm64 ]] || fail 'An Apple Silicon Mac is required. Run Terminal without Rosetta.'
major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)
[[ $major -ge 15 ]] || fail 'macOS 15 or later is required.'
[[ $repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Set DICT_REPOSITORY to the GitHub repository of the publisher.'
[[ $team_id =~ ^[A-Z0-9]{10}$ ]] || fail "Set DICT_RELEASE_TEAM_ID to the Apple Team ID of the publisher."
[[ $version == latest || $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || fail 'Invalid release version.'
destination="$HOME/Applications/Dict Local AI.app"
if /usr/bin/pgrep -f "$destination/Contents/MacOS/DictLocalAI" >/dev/null; then
    fail 'Quit Dict Local AI from the menu bar and retry.'
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ $version == latest ]]; then base="https://github.com/$repository/releases/latest/download"
else base="https://github.com/$repository/releases/download/$version"; fi
fetch() { /usr/bin/curl --fail --location --write-out "\nDownloaded: %{size_download} bytes; average speed: %{speed_download} bytes/s; time: %{time_total} s\n" --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600 "$1" -o "$2"; }
echo 'Downloading Dict Local AI…'
fetch "$base/Dict-Local-AI-macOS-arm64.zip" "$work/Dict-Local-AI-macOS-arm64.zip"
fetch "$base/SHA256SUMS" "$work/SHA256SUMS"
expected=$(awk '$2 == "Dict-Local-AI-macOS-arm64.zip" {print $1}' "$work/SHA256SUMS")
[[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || fail 'The release has no valid checksum.'
actual=$(/usr/bin/shasum -a 256 "$work/Dict-Local-AI-macOS-arm64.zip" | awk '{print $1}')
[[ $actual == "$expected" ]] || fail 'The archive checksum did not match.'
/usr/bin/unzip -Z1 "$work/Dict-Local-AI-macOS-arm64.zip" > "$work/entries"
if awk '/(^\/|(^|\/)\.\.($|\/))/ {bad=1} END {exit !bad}' "$work/entries"; then fail 'The archive contains invalid paths.'; fi
/usr/bin/ditto -x -k "$work/Dict-Local-AI-macOS-arm64.zip" "$work/unpacked"
app="$work/unpacked/Dict Local AI.app"
[[ -x "$app/Contents/MacOS/DictLocalAI" ]] || fail 'The archive has no executable app bundle.'
requirement="anchor apple generic and identifier \"app.dictlocalai.desktop\" and certificate leaf[subject.OU] = \"$team_id\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
/usr/bin/codesign --verify --deep --strict -R "$requirement" "$app" \
  || fail 'The app does not satisfy the expected Developer ID and Team ID.'
/usr/sbin/spctl --assess --type execute --verbose=2 "$app" \
  || fail 'Gatekeeper did not accept the app.'
new_req=$(/usr/bin/codesign -d -r- "$app" 2>&1 | /usr/bin/sed -n 's/^[[:space:]]*designated =>[[:space:]]*//p')
[[ -n "$new_req" && "$new_req" == *'identifier '* && "$new_req" != *'cdhash '* ]] || fail 'The app lacks a stable designated requirement.'
if /usr/bin/codesign -dv "$app" 2>&1 | /usr/bin/grep -q 'Signature=adhoc'; then
  fail 'Ad-hoc signatures cannot preserve TCC grants across rebuilds.'
fi
if [[ -d "$destination" ]]; then
  /usr/bin/codesign --verify --deep --strict "$destination" || fail 'The installed app failed signature verification.'
  old_req=$(/usr/bin/codesign -d -r- "$destination" 2>&1 | /usr/bin/sed -n 's/^[[:space:]]*designated =>[[:space:]]*//p')
  [[ "$new_req" == "$old_req" ]] || fail 'The new signing requirement differs from the installed app. Existing TCC grants were preserved.'
  printf '%s\n' "$old_req" > "$work/old.req"
  /usr/bin/codesign --verify -R "$work/old.req" "$app" >/dev/null 2>&1 || fail 'The new app does not meet the existing code requirement.'
fi
mkdir -p "$HOME/Applications"
staged="$HOME/Applications/.Dict-Local-AI-new-$$.app"
/usr/bin/ditto "$app" "$staged"
backup="$HOME/Applications/.Dict-Local-AI-backup-$$.app"
if [[ -e "$destination" ]]; then mv "$destination" "$backup"; fi
if ! mv "$staged" "$destination"; then
    [[ ! -e "$backup" ]] || mv "$backup" "$destination"
    fail 'Installation failed. The previous app was restored if present.'
fi
if /usr/bin/open "$destination"; then
    for ((attempt=0; attempt<10; attempt++)); do
        if /usr/bin/pgrep -f "$destination/Contents/MacOS/DictLocalAI" >/dev/null; then
            [[ ! -e "$backup" ]] || rm -rf "$backup"
            echo 'Dict Local AI is running. Its icon is in the menu bar.'
            exit 0
        fi
        sleep 1
    done
fi
fail "Launch could not be confirmed. Any previous app is preserved at $backup."
