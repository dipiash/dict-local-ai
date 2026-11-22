#!/bin/bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Signing setup requires macOS.' >&2; exit 1; }
cd "$(dirname "$0")/../.."
source scripts/development/tcc-signing.sh
pin_file="$HOME/.config/dict-local-ai/signing-identity"
valid=$(/usr/bin/security find-identity -v -p codesigning 2>&1 || true)
if [[ -f "$pin_file" ]]; then
  IFS= read -r identity < "$pin_file" || true
  if [[ -n "${identity:-}" ]] && printf '%s\n' "$valid" | /usr/bin/grep -Fq -- "$identity"; then
    echo "A persistent signing certificate is already configured: $identity"
    echo 'Keep the certificate in Keychain to preserve TCC grants across builds.'
    exit 0
  fi
  echo 'The pinned certificate is unavailable. Restore it before updating the installed app.' >&2
  echo "Pinned SHA-1: ${identity:-<empty>}" >&2
  exit 1
fi
if printf '%s\n' "$valid" | /usr/bin/grep -Fq '"Dict Local AI Local Signing"'; then
  echo 'Found the Dict Local AI Local Signing certificate.'
  echo 'Run task install to pin the certificate SHA-1 on the first successful signing.'
  exit 0
fi
if /usr/bin/security find-certificate -a -c 'Dict Local AI Local Signing' -p "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null | /usr/bin/grep -q 'BEGIN CERTIFICATE'; then
  echo 'The certificate exists but is missing from the valid identities list.' >&2
  echo 'Check the private key, expiration and code signing trust in Keychain Access.' >&2
  exit 1
fi
cat <<'GUIDE'
One-time local signing setup:
  1. Open Keychain Access.
  2. Choose Keychain Access → Certificate Assistant → Create a Certificate…
  3. Name: Dict Local AI Local Signing
     Identity Type: Self Signed Root
     Certificate Type: Code Signing
     Select “Let me override defaults” and choose a long validity period,
     such as 3650 days. Keep the private key in the login keychain.
  4. Verify in Terminal:
       security find-identity -v -p codesigning
     The valid identities list should show Dict Local AI Local Signing.
  5. Run task install to pin the signing identity on this Mac.

Keep the certificate and private key for future builds.
Install separately and grant permissions on each Mac.
Public distribution requires Developer ID signing and notarization.
GUIDE
/usr/bin/open -a 'Keychain Access' || true
