#!/bin/bash
set -euo pipefail
app="$HOME/Applications/Dict Local AI.app"
if /usr/bin/pgrep -x DictLocalAI >/dev/null; then
    echo 'Quit every running copy of Dict Local AI first.' >&2; exit 1
fi
if [[ ${1:-} == --purge ]]; then
    printf 'Remove the app, TCC grants, models, history and preferences? Enter DELETE: '
    read -r answer
    answer=${answer%$'\r'}
    if [[ $answer != DELETE ]]; then
        echo 'Purge cancelled. The app and its data were preserved.' >&2
        exit 1
    fi
fi
# Launch Services needs the installed bundle for the reset.
if [[ -d "$app" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
fi
if ! /usr/bin/tccutil reset All app.dictlocalai.desktop; then
    echo 'TCC reset failed. The app remains installed.' >&2
    echo 'Check macOS settings or run task permissions:doctor.' >&2
    exit 1
fi
[[ ! -e "$app" ]] || /bin/rm -rf "$app"
if [[ ${1:-} == --purge ]]; then
    /bin/rm -rf "$HOME/Library/Application Support/Dict Local AI"
    /bin/rm -rf "$HOME/Library/Logs/Dict Local AI"
    /usr/bin/defaults delete app.dictlocalai.desktop 2>/dev/null || true
    echo 'Removed the app, TCC grants and user data.'
else
    echo 'Removed the app and its TCC grants. Models, history and preferences were preserved.'
fi
