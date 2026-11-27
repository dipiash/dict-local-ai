#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

[[ $(uname -s) == Darwin ]] || { echo 'DMG creation requires macOS.' >&2; exit 2; }
[[ $# == 2 ]] || { echo 'Usage: scripts/release/make-dmg.sh APP_PATH OUTPUT_DMG' >&2; exit 2; }
app="$1"
output="$2"
[[ -d "$app/Contents" ]] || { echo "App bundle not found: $app" >&2; exit 2; }
[[ -f Resources/App/AppIcon.icns ]] || { echo 'Missing existing application icon.' >&2; exit 2; }
[[ -f Resources/Installer/DMGBackground.png ]] || { echo 'Missing DMG background.' >&2; exit 2; }

# Use verified wheels to write Finder metadata.
requirements='scripts/release/requirements.txt'
venv=".build/tools/dmg-layout-$(shasum -a 256 "$requirements" | awk '{print $1}')"
if [[ ! -f "$venv/.verified" ]] || [[ ! -x "$venv/bin/python3" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/python3" -m pip install --disable-pip-version-check --no-input \
    --only-binary=:all: --require-hashes -r "$requirements"
  "$venv/bin/python3" -c 'import ds_store, mac_alias'
  touch "$venv/.verified"
fi

stage=$(mktemp -d)
temporary_output="${output%.dmg}.building-$$.dmg"
trap 'rm -rf "$stage"; rm -f "$temporary_output"' EXIT
mkdir -p "$stage/.background"
/usr/bin/ditto "$app" "$stage/Dict Local AI.app"
cp Resources/Installer/DMGBackground.png "$stage/.background/background.png"
cp Resources/App/AppIcon.icns "$stage/.VolumeIcon.icns"
ln -s /Applications "$stage/Applications"

"$venv/bin/python3" scripts/release/write-dmg-layout.py "$stage/.DS_Store"

# Finder needs this flag to show the custom volume icon.
if setfile=$(xcrun --find SetFile 2>/dev/null); then
  "$setfile" -a C "$stage"
fi

for attempt in 1 2 3; do
  if output_log=$(LC_ALL=C /usr/bin/hdiutil create \
    -volname 'Dict Local AI' \
    -srcfolder "$stage" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$temporary_output" 2>&1); then
    printf '%s\n' "$output_log"
    break
  else
    status=$?
    printf '%s\n' "$output_log" >&2
    if [[ "$attempt" -eq 3 || "$output_log" != *"Resource busy"* ]]; then
      exit "$status"
    fi
    sleep "$((attempt * 2))"
  fi
done

mv -f "$temporary_output" "$output"
echo "Created DMG without opening Finder: $output"
