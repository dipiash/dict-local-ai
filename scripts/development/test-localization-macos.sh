#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $(uname -s) == Darwin ]] || { echo 'Localization DMG tests require macOS.' >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/dict-localization.XXXXXX")"
mounted=0
cleanup() {
  if (( mounted )); then
    hdiutil detach "$work/mounted" || return
  fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/mounted"

bash scripts/build/build.sh --prepare-only "$work"
bash scripts/release/make-dmg.sh "$work/Dict Local AI.app" "$work/DictLocalAI.dmg"
hdiutil attach "$work/DictLocalAI.dmg" -readonly -nobrowse -mountpoint "$work/mounted" >/dev/null
mounted=1
app="$work/mounted/Dict Local AI.app"
for lang in en ru; do
  for resource in Localizable.strings Localizable.stringsdict InfoPlist.strings; do
    /usr/bin/plutil -lint "$app/Contents/Resources/$lang.lproj/$resource"
  done
done
python3 scripts/development/verify-localization-runtime.py "$app"
