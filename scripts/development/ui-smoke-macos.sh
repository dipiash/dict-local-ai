#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "macOS required for native UI smoke test" >&2
  exit 2
fi
APP="${DICT_APP_PATH:-$HOME/Applications/Dict Local AI.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
open "$APP"
# Grant Accessibility to Terminal before running this check.
osascript <<'APPLESCRIPT'
on visibleTextContains(needle)
  tell application "System Events"
    tell process "Dict Local AI"
      if (count of windows) < 1 then error "No workspace window"
      set uiItems to entire contents of front window
      repeat with uiItem in uiItems
        try
          set uiName to name of uiItem as text
          if uiName contains needle then return true
        end try
        try
          set uiValue to value of uiItem as text
          if uiValue contains needle then return true
        end try
      end repeat
    end tell
  end tell
  return false
end visibleTextContains

on requireRenderedText(labelEN, labelRU, scenario)
  repeat 6 times
    if my visibleTextContains(labelEN) or my visibleTextContains(labelRU) then return
    delay 0.5
  end repeat
  error "Blank or unrendered workspace: " & scenario & " (missing accessible text: " & labelEN & " / " & labelRU & ")"
end requireRenderedText

tell application "System Events"
  tell process "Dict Local AI"
    set frontmost to true
    if (count of windows) < 1 then error "No workspace window"
    if name of front window is not "Dict Local AI" then error "Unexpected workspace title"
  end tell
  keystroke "1" using {command down}
end tell
my requireRenderedText("Dictation Editor", "Редактор диктовки", "Dictation")

tell application "System Events" to keystroke "2" using {command down}
my requireRenderedText("Turn audio files into text.", "Преобразуйте аудиофайлы в текст", "Files")

tell application "System Events" to keystroke "5" using {command down}
my requireRenderedText("General", "Основные", "Settings")

-- Repeat the critical navigation sequence. A layout invalidation can appear
-- only on a second Files visit, after SwiftUI has cached a previous tree.
repeat 3 times
  tell application "System Events" to keystroke "2" using {command down}
  my requireRenderedText("Turn audio files into text.", "Преобразуйте аудиофайлы в текст", "Files after repeat navigation")
  tell application "System Events" to keystroke "1" using {command down}
  my requireRenderedText("Dictation Editor", "Редактор диктовки", "Dictation after Files")
end repeat
APPLESCRIPT
echo "PASS: SwiftUI content survives repeated Dictation ↔ Files navigation and Settings"
