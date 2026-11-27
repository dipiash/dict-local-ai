#!/usr/bin/env bash
# Live check: after a dictation is pasted, the app puts the previous clipboard back.
# It changes your clipboard, opens a TextEdit document, records through the microphone
# and speaks through the speakers. Run it only when you are away from the computer.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./ui-data-dir-lib.sh

MARKER="clipboard-marker-$RANDOM-$RANDOM"
USER_CLIPBOARD=""
CLIPBOARD_SAVED=0
DOC_NAME=""

clipboard_types="$(osascript -e 'clipboard info' 2>/dev/null || true)"
# Only plain text is saved and restored here, so a richer clipboard would be lost.
if [[ -n "$clipboard_types" ]] && grep -Eq 'PNGf|TIFF|furl|RTF|HTML|«class' <<<"$(sed 's/«class utf8»//g; s/«class ut16»//g' <<<"$clipboard_types")"; then
  ui_fail "The clipboard holds more than plain text. Copy a text first and run again."
fi

restore_environment() {
  if [[ -n "$DOC_NAME" ]]; then
    osascript -e "tell application \"TextEdit\" to close document \"$DOC_NAME\" saving no" >/dev/null 2>&1 || true
  fi
  if [[ "$CLIPBOARD_SAVED" == 1 ]]; then printf '%s' "$USER_CLIPBOARD" | pbcopy; fi
}
# shellcheck disable=SC2034
UI_CLEANUP_HOOK=restore_environment

ui_start

USER_CLIPBOARD="$(pbpaste)"
CLIPBOARD_SAVED=1
printf '%s' "$MARKER" | pbcopy

DOC_NAME="$(osascript <<'APPLESCRIPT'
tell application "TextEdit"
  activate
  set d to make new document
  return name of d
end tell
APPLESCRIPT
)"
sleep 1

STARTS="$(ui_log_count 'dictation] microphone_started')"
osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Dict Local AI"
    click menu bar item 1 of menu bar 2
    click (first menu item of menu 1 of menu bar item 1 of menu bar 2 whose name is "Hands-free Recording" or name is "Запись без удержания")
  end tell
end tell
APPLESCRIPT
ui_wait_for_log_event 'dictation] microphone_started' "$STARTS" 30 || ui_fail "Dictation did not start (models or microphone permission?)"
sleep 1
say "This is a short clipboard restore test."
sleep 1
RESTORED="$(ui_log_count 'insertion] clipboard_restor')"
osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Dict Local AI"
    click menu bar item 1 of menu bar 2
    click (first menu item of menu 1 of menu bar item 1 of menu bar 2 whose name is "Hands-free Recording" or name is "Запись без удержания")
  end tell
end tell
APPLESCRIPT
ui_wait_for_log_event 'insertion] clipboard_restor' "$RESTORED" 90 || ui_fail "No clipboard_restored event after the dictation"
grep -q 'clipboard_restored' "$UI_LOG_FILE" || ui_fail "The clipboard was not restored: $(grep 'clipboard_restore_skipped' "$UI_LOG_FILE" | tail -1)"
[[ "$(pbpaste)" == "$MARKER" ]] || ui_fail "The clipboard does not hold the original text after the dictation"
INSERTED="$(osascript -e "tell application \"TextEdit\" to get text of document \"$DOC_NAME\"")"
[[ -n "$INSERTED" ]] || ui_fail "The dictated text was not pasted into TextEdit"
echo "PASS: ui:clipboard-restore"
