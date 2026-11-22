#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $(uname -s) == Darwin ]] || { echo 'Building the app requires macOS 15+ and Xcode 16+.' >&2; exit 1; }
xcrun --find swift >/dev/null || { echo 'Install Xcode or Command Line Tools.' >&2; exit 1; }
prepare_dir=""
if [[ $# != 0 ]]; then
  [[ $# == 2 && $1 == --prepare-only && $2 == /* && -d $2 ]] \
    || { echo 'Usage: build.sh [--prepare-only EXISTING_ABSOLUTE_DIRECTORY]' >&2; exit 2; }
  prepare_dir="$2"
fi
echo 'Building Dict Local AI for Apple Silicon…'
echo '[1/5] Resolving dependencies and compiling'
checkout="$(pwd -P)"
binary_dir=$(/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon -c release --arch arm64 --show-bin-path)
overlay=$(python3 scripts/build/prepare-portable-resources.py "$binary_dir" "$checkout/.build/portable-resources")
/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon -c release --arch arm64 -debug-info-format none \
  -Xswiftc -vfsoverlay -Xswiftc "$overlay" \
  -Xswiftc -debug-prefix-map -Xswiftc "$checkout=." \
  -Xswiftc -file-prefix-map -Xswiftc "$checkout=." \
  -Xcc "-fdebug-prefix-map=$checkout=." -Xcxx "-fdebug-prefix-map=$checkout=." 2>&1 | awk '{ sub(/^\[[0-9]+\/[0-9]+\] /, "    "); print; fflush() }'
echo '[2/5] Preparing the app bundle and executable'
app="${prepare_dir:-dist}/Dict Local AI.app"
/bin/rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/DictLocalAI" "$app/Contents/MacOS/DictLocalAI"
/usr/bin/strip -S "$app/Contents/MacOS/DictLocalAI"
cp Resources/App/Info.plist "$app/Contents/Info.plist"
echo '[3/5] Setting the version and copying resources and licenses'
version="${DICT_BUILD_VERSION:-}"
if [[ -z "$version" ]]; then
  tag=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
  if [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version="${tag#v}"
  else
    version="0.1.0"
  fi
fi
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $version" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md LICENSE "$app/Contents/Resources/"
cp -R Resources/Licenses "$app/Contents/Resources/"
cp Resources/App/AppIcon.icns Resources/App/BrandMark.png "$app/Contents/Resources/"
cp -R Resources/App/en.lproj Resources/App/ru.lproj "$app/Contents/Resources/"
cp -R "$binary_dir/FluidAudio_FluidAudio.bundle" "$app/Contents/Resources/"
python3 scripts/build/verify-portable-bundle.py "$app"
if [[ -n "$prepare_dir" ]]; then exit 0; fi
echo '[4/5] Signing the app'
# TCC follows the signing identity across builds.
pin_file="$HOME/.config/dict-local-ai/signing-identity"
identity="${DICT_CODESIGN_IDENTITY:-}"
pinned=''
if [[ -f "$pin_file" ]]; then
  IFS= read -r pinned < "$pin_file" || true
  if [[ -n "$identity" && "$identity" != "$pinned" ]]; then
    echo 'Error: the requested signing identity differs from the pinned one. The update would break TCC grants.' >&2
    echo "Pinned identity: $pinned" >&2
    exit 1
  fi
  identity="$pinned"
fi
available=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
if [[ -z "$identity" ]]; then
  for prefix in '"Dict Local AI Local Signing"' '"Apple Development:' '"Developer ID Application:'; do
    candidates=$(printf '%s\n' "$available" | /usr/bin/grep -F "$prefix" | /usr/bin/awk '{print $2}' || true)
    count=$(printf '%s\n' "$candidates" | /usr/bin/grep -c . || true)
    if (( count > 1 )); then
      echo "Multiple signing certificates match $prefix. Specify one SHA-1:" >&2
      echo 'DICT_CODESIGN_IDENTITY=<SHA1> task install' >&2
      exit 1
    fi
    if (( count == 1 )); then
      identity="$candidates"
      break
    fi
  done
fi
if [[ -z "$identity" ]]; then
  echo 'A persistent code signing certificate is required.' >&2
  echo 'Check: security find-identity -v -p codesigning' >&2
  echo 'Set up local signing: task signing:setup' >&2
  echo 'To select a certificate: DICT_CODESIGN_IDENTITY=<SHA1> task install' >&2
  exit 1
fi
if ! printf '%s\n' "$available" | /usr/bin/grep -Fq -- "$identity"; then
  echo "Certificate $identity is unavailable or untrusted in Keychain." >&2
  echo 'Check: security find-identity -v -p codesigning' >&2
  exit 1
fi
/usr/bin/codesign --force --timestamp=none --sign "$identity" "$app"
requirement=$(/usr/bin/codesign -d -r- "$app" 2>&1)
if [[ "$requirement" == *'cdhash '* ]]; then
  echo 'The signature uses a CDHash requirement that cannot preserve TCC grants across builds.' >&2
  exit 1
fi
source scripts/development/tcc-signing.sh
dict_tcc_assert_stable_signature "$app"
mkdir -p "$(dirname "$pin_file")"
printf '%s\n' "$identity" > "$pin_file"
chmod 600 "$pin_file"
echo "Code signing identity: $identity"
printf '%s\n' "$requirement" | /usr/bin/grep 'designated =>' || true
echo '[5/5] Verifying the signature'
/usr/bin/codesign --verify --deep --strict "$app"
echo "Built: $app"
