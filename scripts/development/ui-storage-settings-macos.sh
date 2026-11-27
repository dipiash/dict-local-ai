#!/usr/bin/env bash
# Checks Settings > Storage on a seeded test data folder: audio size, "Delete all audio",
# the "Save audio" switch and the logs button.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./ui-data-dir-lib.sh
ui_start

DB="$UI_DATA/recordings.sqlite3"
audio_files() { find "$UI_DATA" -type f -name '*.m4a' | wc -l | tr -d ' '; }
saved_text_rows() { sqlite3 -readonly "$DB" "SELECT count(*) FROM recording_segments WHERE text LIKE 'The first sample%'"; }

[[ "$(audio_files)" -ge 1 ]] || ui_fail "The seeded record has no audio file"
[[ "$(saved_text_rows)" -ge 1 ]] || ui_fail "The seeded record has no text"

# 1. The size of the saved audio is shown.
ui_osascript <<'APPLESCRIPT'
my openSection("5", {"General", "Основные"}, "Settings")
my clickText({"Storage", "Хранение"})
set usage to my waitById("settings-audio-usage", 10)
repeat 20 times
  set shown to my attrOf(usage, "AXValue")
  if shown contains "MB" or shown contains "МБ" then exit repeat
  delay 0.5
end repeat
if not (shown contains "MB" or shown contains "МБ") then error "Audio size is not shown: " & shown
if not (shown contains "1 file" or shown contains "1 файл") then error "Expected one audio file: " & shown
APPLESCRIPT
echo "PASS: audio size is shown"

# 2. Delete all audio: the sound goes, the text stays.
BEFORE_REMOVED="$(ui_log_count 'history-audio] removed_all')"
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitById("settings-remove-all-audio", 5))
delay 1
set confirmButton to my findByRoleAndText("AXButton", {"Delete audio", "Удалить звук"})
if confirmButton is missing value then error "Confirmation button not found"
my requireFront()
tell application "System Events" to click confirmButton
APPLESCRIPT
ui_wait_for_log_event 'history-audio] removed_all' "$BEFORE_REMOVED" 15 || ui_fail "No removed_all event"
[[ "$(audio_files)" -eq 0 ]] || ui_fail "Audio files are still in the test folder"
[[ "$(saved_text_rows)" -ge 1 ]] || ui_fail "The text of the record is gone"
ui_osascript <<'APPLESCRIPT'
set usage to my findById("settings-audio-usage")
repeat 20 times
  set shown to my attrOf(usage, "AXValue")
  if shown contains "Audio: 0 MB" or shown contains "Звук: 0 МБ" then exit repeat
  delay 0.5
end repeat
if not (shown contains "Audio: 0 MB" or shown contains "Звук: 0 МБ") then error "Audio size did not drop to 0: " & shown
APPLESCRIPT
echo "PASS: all audio deleted, text kept"

# 3. Turn "Save audio" off and read it back from the test settings file.
PREFS="$UI_DATA/preferences.json"
ui_osascript <<'APPLESCRIPT'
set toggle to my findSwitchAfterText({"Save audio", "Сохранять звук"})
if toggle is missing value then error "Save audio switch not found"
my requireFront()
tell application "System Events" to click toggle
APPLESCRIPT
waited=0
until grep -q '"historyAudio" : false' "$PREFS" 2>/dev/null; do
  sleep 0.5
  waited=$((waited + 1))
  [[ "$waited" -le 10 ]] || ui_fail "historyAudio is not false in $PREFS"
done
echo "PASS: Save audio off is stored in the test settings"

# 4. The logs button opens a Finder window for the test log folder.
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitById("settings-open-logs", 5))
repeat 20 times
  tell application "System Events"
    if exists (window "ui-test-logs" of process "Finder") then exit repeat
  end tell
  delay 0.5
end repeat
tell application "System Events"
  if not (exists (window "ui-test-logs" of process "Finder")) then error "Finder window for the logs folder did not open"
  tell process "Finder"
    click (first button of window "ui-test-logs" whose subrole is "AXCloseButton")
  end tell
end tell
APPLESCRIPT
echo "PASS: Open logs folder opens Finder"
echo "PASS: ui:storage-settings"
