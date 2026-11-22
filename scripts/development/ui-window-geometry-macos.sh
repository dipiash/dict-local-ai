#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "macOS required for native window geometry test" >&2
  exit 2
fi
APP="${DICT_APP_PATH:-$HOME/Applications/Dict Local AI.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
open "$APP"
# Grant Automation and Accessibility to Terminal first.
osascript <<'APPLESCRIPT'
on assertClose(actualSize, expectedSize, scenario)
  set differenceWidth to (item 1 of actualSize) - (item 1 of expectedSize)
  set differenceHeight to (item 2 of actualSize) - (item 2 of expectedSize)
  if differenceWidth < 0 then set differenceWidth to -differenceWidth
  if differenceHeight < 0 then set differenceHeight to -differenceHeight
  if (differenceWidth > 3) or (differenceHeight > 3) then
    error scenario & ": changed from " & (expectedSize as text) & " to " & (actualSize as text)
  end if
end assertClose

tell application "System Events"
  tell process "Dict Local AI"
    set frontmost to true
    if (count of windows) < 1 then error "Workspace window is missing"
    set originalSize to size of front window
  end tell
  try
    keystroke "2" using {command down}
    delay 1
    tell process "Dict Local AI" to set afterFiles to size of front window
    my assertClose(afterFiles, originalSize, "Opening Files")

    keystroke "4" using {command down}
    delay 1
    tell process "Dict Local AI" to set afterHistory to size of front window
    my assertClose(afterHistory, originalSize, "Opening History")

    keystroke "5" using {command down}
    delay 1
    tell process "Dict Local AI" to set afterSettings to size of front window
    my assertClose(afterSettings, originalSize, "Opening Settings")

    set targetHeight to item 2 of originalSize
    if targetHeight > 630 then
      set targetHeight to targetHeight - 60
    else
      set targetHeight to targetHeight + 60
    end if
    set targetSize to {item 1 of originalSize, targetHeight}
    tell process "Dict Local AI" to set size of front window to targetSize
    delay 1
    tell process "Dict Local AI" to set afterFirstResize to size of front window
    my assertClose(afterFirstResize, targetSize, "First vertical resize")

    keystroke "2" using {command down}
    delay 1
    tell process "Dict Local AI" to set afterResizeAndFiles to size of front window
    my assertClose(afterResizeAndFiles, targetSize, "Files after manual resize")
  on error messageText number errorNumber
    tell process "Dict Local AI" to set size of front window to originalSize
    error messageText number errorNumber
  end try
  tell process "Dict Local AI" to set size of front window to originalSize
end tell
APPLESCRIPT
echo "PASS: section transitions and first resize preserve window dimensions"
