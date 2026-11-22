#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $(uname -s) == Darwin ]] || { echo "macOS required" >&2; exit 2; }
: "${DICT_RELEASE_DEVELOPER_ID:?Set Developer ID Application signing identity (SHA-1 or full name)}"
: "${DICT_NOTARY_PROFILE:?Create notarytool keychain profile and set its name}"
APP="dist/Dict Local AI.app"
[[ -d "$APP" ]] || { echo 'Build the local app first: task dmg' >&2; exit 1; }
python3 scripts/build/verify-portable-bundle.py "$APP"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/Dict Local AI.app"
/usr/bin/codesign --force --options runtime --timestamp \
  --entitlements Resources/Installer/Release.entitlements \
  --sign "$DICT_RELEASE_DEVELOPER_ID" "$STAGE/Dict Local AI.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGE/Dict Local AI.app"
SIGNED_APP="$STAGE/Dict Local AI.app"
ZIP="Dict-Local-AI-macOS-arm64.zip"
DMG="Dict-Local-AI-notarized.dmg"
OUTPUT="dist/public"
[[ ! -e "$OUTPUT" ]] || { echo "Move the previous public release directory away: $OUTPUT" >&2; exit 1; }
RELEASE=$(mktemp -d dist/.public-release.XXXXXXXX)
trap 'rm -rf "$STAGE" "$RELEASE"' EXIT
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP" "$STAGE/$ZIP"
/usr/bin/xcrun notarytool submit "$STAGE/$ZIP" --keychain-profile "$DICT_NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$SIGNED_APP"
/usr/bin/xcrun stapler validate "$SIGNED_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$SIGNED_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP" "$RELEASE/$ZIP"

bash scripts/release/make-dmg.sh "$SIGNED_APP" "$RELEASE/$DMG"
/usr/bin/codesign --force --timestamp --sign "$DICT_RELEASE_DEVELOPER_ID" "$RELEASE/$DMG"
/usr/bin/xcrun notarytool submit "$RELEASE/$DMG" --keychain-profile "$DICT_NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$RELEASE/$DMG"
/usr/bin/xcrun stapler validate "$RELEASE/$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$RELEASE/$DMG"
(cd "$RELEASE" && shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS)
mv "$RELEASE" "$OUTPUT"
echo "Notarized release files are ready in $OUTPUT"
