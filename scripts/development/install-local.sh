#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/development/tcc-signing.sh
source scripts/development/tcc-signing.sh
app="$HOME/Applications/Dict Local AI.app"
if /usr/bin/pgrep -x DictLocalAI >/dev/null; then
    echo 'Quit every running copy of Dict Local AI and retry.' >&2; exit 1
fi
if [[ -e '/Applications/Dict Local AI.app' ]]; then
    echo 'A second copy was found in /Applications. Keep ~/Applications/Dict Local AI.app.' >&2
    echo 'Quit the app and remove the second copy manually. This operation leaves TCC grants intact.' >&2
    exit 1
fi
bash scripts/build/build.sh
if /usr/bin/pgrep -x DictLocalAI >/dev/null; then
    echo 'Quit every running copy of Dict Local AI and retry.' >&2; exit 1
fi
/bin/mkdir -p "$HOME/Applications"
staging="$HOME/Applications/.Dict Local AI.staging.$$.app"
backup="$HOME/Applications/.Dict Local AI.backup.$$.app"
cleanup() {
    /bin/rm -rf "$staging"
    if [[ -d "$backup" && ! -d "$app" ]]; then
        /bin/mv "$backup" "$app"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
/usr/bin/ditto 'dist/Dict Local AI.app' "$staging"
dict_tcc_assert_stable_signature "$staging"
dict_tcc_check_upgrade "$app" "$staging"
if [[ -d "$app" ]]; then /bin/mv "$app" "$backup"; fi
if ! /bin/mv "$staging" "$app"; then
    echo 'Replacement failed. The previous copy will be restored.' >&2
    exit 1
fi
if ! /usr/bin/codesign --verify --deep --strict "$app"; then
    /bin/rm -rf "$app"
    echo 'The installed app failed verification. Restoring the previous copy.' >&2
    exit 1
fi
/bin/rm -rf "$backup"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
/usr/bin/open "$app"
echo 'Updated with TCC grants preserved. For meeting capture, grant System Audio Recording.'
