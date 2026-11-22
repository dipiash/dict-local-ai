#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/development/tcc-signing.sh
source scripts/development/tcc-signing.sh
app="$DICT_TCC_INSTALL_PATH"
pin="$HOME/.config/dict-local-ai/signing-identity"
status=0
printf '%s\n' '=== Code Signing identities in Keychain ==='
/usr/bin/security find-identity -v -p codesigning || true
printf '\n%s\n' '=== Running copies ==='
/usr/bin/pgrep -fl DictLocalAI || true
if [[ -d '/Applications/Dict Local AI.app' ]]; then
  echo 'WARNING: Another copy exists in /Applications. Keep one installed copy.' >&2
  status=1
fi
printf '\n%s\n' '=== Installed application ==='
if [[ -d "$app" ]]; then
  echo "Location: $app"
  if ! dict_tcc_assert_stable_signature "$app"; then
    echo 'ERROR: the installed copy lacks a stable code identity.' >&2
    status=1
  fi
  /usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/grep -E 'Identifier=|Authority=|TeamIdentifier=|Signature=' || true
  echo "Designated Requirement: $(dict_tcc_requirement "$app" || true)"
else
  echo "Missing app: $app. Run task install."
fi
printf '\n%s\n' '=== Local build (not for granting permissions) ==='
if [[ -d 'dist/Dict Local AI.app' ]]; then
  /usr/bin/codesign -dv --verbose=4 'dist/Dict Local AI.app' 2>&1 \
    | /usr/bin/grep -E 'Identifier=|Authority=|Signature=' || true
  if [[ -d "$app" ]]; then
    if ! dict_tcc_check_upgrade "$app" 'dist/Dict Local AI.app'; then
      echo 'WARNING: the local build cannot safely replace the installed app.' >&2
      status=1
    fi
  fi
fi
printf '\n%s\n' '=== Pinned identity ==='
if [[ -f "$pin" ]]; then
  IFS= read -r identity < "$pin" || true
  echo "Pinned certificate SHA-1: ${identity:-<empty>}"
  if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "${identity:-NO-IDENTITY}"; then
    echo 'ERROR: the certificate is no longer available in Keychain.' >&2
    status=1
  fi
else
  echo 'No signing identity is pinned. Run task signing:setup and task install.'
fi
printf '\n%s\n' '=== Runtime permissions ==='
echo 'The running app checks effective Accessibility, audio capture, and input permissions via system APIs.'
echo 'System Settings can display a stale TCC record.'
echo 'Reserve task permissions:reset for explicit permission troubleshooting.'
exit "$status"
