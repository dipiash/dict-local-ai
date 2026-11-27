#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "macOS required for native busy-notice test" >&2
  exit 2
fi
APP="${DICT_APP_PATH:-$HOME/Applications/Dict Local AI.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
LOG_DIR="${DICT_LOG_DIR:-$HOME/Library/Logs/Dict Local AI}"
open "$APP"
sleep 2
# Grant Accessibility to Terminal first. The test starts a real meeting and stops it.
PID="$(osascript -e 'tell application "System Events" to unix id of process "Dict Local AI"')"
LOG_FILE="$(find "$LOG_DIR" -maxdepth 1 -name "session-*-$PID.log" | head -1)"
[[ -n "$LOG_FILE" ]] || { echo "No session log for pid $PID in $LOG_DIR" >&2; exit 1; }
count_rejected() { grep -c 'dictation start_rejected.*busy=meeting' "$LOG_FILE" || true; }
BEFORE="$(count_rejected)"

osascript <<'APPLESCRIPT'
on panelWindow()
  tell application "System Events"
    tell process "Dict Local AI"
      repeat with w in windows
        try
          if (count of (buttons of w whose name is "Finish" or name is "Завершить")) > 0 then return w
        end try
      end repeat
    end tell
  end tell
  return missing value
end panelWindow

on panelHasNotice()
  set w to my panelWindow()
  if w is missing value then return false
  tell application "System Events"
    tell process "Dict Local AI"
      repeat with t in (static texts of w)
        try
          set s to value of t as text
          if s contains "Dictation is not available" or s contains "диктовка недоступна" then return true
        end try
      end repeat
    end tell
  end tell
  return false
end panelHasNotice

on bottomEdge(w)
  tell application "System Events"
    tell process "Dict Local AI"
      return (item 2 of (position of w)) + (item 2 of (size of w))
    end tell
  end tell
end bottomEdge

on finishMeeting()
  set w to my panelWindow()
  if w is missing value then return
  tell application "System Events"
    tell process "Dict Local AI"
      click (first button of w whose name is "Finish" or name is "Завершить")
    end tell
  end tell
end finishMeeting

tell application "System Events"
  tell process "Dict Local AI"
    set frontmost to true
    if (count of windows) < 1 then error "No workspace window"
  end tell
end tell
if my panelWindow() is not missing value then error "A meeting is already running; refusing to touch it"

-- 1. Start a meeting from the Meetings tab.
tell application "System Events"
  keystroke "3" using {command down}
  delay 1
  tell process "Dict Local AI"
    set startButton to missing value
    repeat with uiItem in (entire contents of window "Dict Local AI")
      try
        if role of uiItem is "AXButton" and (name of uiItem is "Start Meeting" or name of uiItem is "Начать встречу") then
          set startButton to uiItem
          exit repeat
        end if
      end try
    end repeat
  end tell
end tell
if startButton is missing value then error "Start Meeting button not found (models not ready, or a meeting is running)"
tell application "System Events" to click startButton

try
  set started to false
  repeat 60 times
    if my panelWindow() is not missing value then
      set started to true
      exit repeat
    end if
    delay 0.5
  end repeat
  if not started then error "Meeting panel did not appear within 30 s"
  delay 1

  -- 2. Drag the panel to another place and remember where it is.
  set w to my panelWindow()
  tell application "System Events"
    tell process "Dict Local AI"
      set oldPos to position of w
      set newX to (item 1 of oldPos)
      if newX > 400 then
        set newX to newX - 300
      else
        set newX to newX + 300
      end if
      set newY to (item 2 of oldPos)
      if newY > 400 then
        set newY to newY - 250
      else
        set newY to newY + 40
      end if
      set position of w to {newX, newY}
    end tell
  end tell
  delay 0.5
  set w to my panelWindow()
  set movedBottom to my bottomEdge(w)
  tell application "System Events" to tell process "Dict Local AI" to set movedPos to position of w
  if (item 1 of movedPos) is (item 1 of oldPos) and (item 2 of movedPos) is (item 2 of oldPos) then error "Panel did not move"

  -- 3. Dictation attempt through the menu bar item (no Fn needed).
  tell application "System Events"
    tell process "Dict Local AI"
      click menu bar item 1 of menu bar 2
      click (first menu item of menu 1 of menu bar item 1 of menu bar 2 whose name is "Hands-free Recording" or name is "Запись без удержания")
    end tell
  end tell
  set clickedAt to (current date)

  -- 4. The notice shows, the panel stays, the notice goes after about 3 s.
  set seen to false
  repeat 12 times
    if my panelHasNotice() then
      set seen to true
      exit repeat
    end if
    delay 0.2
  end repeat
  if not seen then error "Busy notice did not appear in the meeting panel (is dictation enabled?)"
  set w to my panelWindow()
  set noticeBottom to my bottomEdge(w)
  set drift to noticeBottom - movedBottom
  if drift < 0 then set drift to -drift
  if drift > 2 then error "Panel bottom edge moved by " & drift & " pt when the notice appeared"
  repeat while ((current date) - clickedAt) < 5
    delay 0.2
  end repeat
  if my panelHasNotice() then error "Busy notice is still shown 5 s after the attempt"
on error messageText number errorNumber
  my finishMeeting()
  error messageText number errorNumber
end try

-- 5. Stop the meeting. The saved record stays in History; the test does not delete it.
my finishMeeting()
delay 1
APPLESCRIPT

AFTER="$(count_rejected)"
if [[ "$AFTER" -le "$BEFORE" ]]; then
  echo "FAIL: no 'dictation start_rejected ... busy=meeting' line in $LOG_FILE" >&2
  exit 1
fi
echo "PASS: busy notice shown, panel kept its place, notice went away, log line present"
echo "NOTE: tray menu was used instead of the Fn key, so the hotkey path itself is not verified"
echo "NOTE: the test meeting may remain in History; delete it there if you do not need it"
