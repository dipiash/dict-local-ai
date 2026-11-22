#!/bin/bash
set -euo pipefail
app="$HOME/Applications/Dict Local AI.app"
[[ -d "$app" ]] || { echo 'Run task install first.' >&2; exit 1; }
if pgrep -f "$app/Contents/MacOS/DictLocalAI" >/dev/null; then
    echo 'Quit Dict Local AI from the menu bar first.' >&2
    exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
/usr/bin/tccutil reset All app.dictlocalai.desktop
echo 'Dict Local AI permissions were reset. Grant access again to the installed copy.'
if [[ ${1:-} != --no-open ]]; then /usr/bin/open "$app"; fi
