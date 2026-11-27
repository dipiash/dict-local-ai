#!/usr/bin/env bash
# Checks listening in History on a seeded test data folder: Listen button and per-segment play buttons.
# Facts come from the screen and from the log of the test copy.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./ui-data-dir-lib.sh
ui_start

STARTED='history-audio] play_started'
ENDED='history-audio] play_ended'

NAV="$(ui_log_count 'section_selected section=history')"
ui_osascript <<'APPLESCRIPT'
my openSection("4", {"UI test recording"}, "History")
my clickText({"UI test recording"})
APPLESCRIPT
ui_wait_for_log_event 'section_selected section=history' "$NAV" 10 || ui_fail "History was not opened"
ui_wait_for_log_event 'history-ui] draft_selected has_selection=true' 0 10 || ui_fail "The seeded record was not selected"
echo "PASS: History opens and the seeded record is selected"

# 1. Listen button on the toolbar starts and stops the sound.
BEFORE="$(ui_log_count "$STARTED")"
ui_osascript <<'APPLESCRIPT'
set b to my waitByAttr("AXButton", "AXHelp", {"Listen", "Stop", "Прослушать", "Остановить"}, 10)
my requireFront()
tell application "System Events" to click b
APPLESCRIPT
ui_wait_for_log_event "$STARTED" "$BEFORE" 10 || ui_fail "No play_started after the Listen button"
echo "PASS: Listen button starts the sound"
END_BEFORE="$(ui_log_count "$ENDED")"
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitByAttr("AXButton", "AXHelp", {"Listen", "Stop", "Прослушать", "Остановить"}, 5))
APPLESCRIPT
ui_wait_for_log_event "$ENDED" "$END_BEFORE" 10 || ui_fail "No play_ended after the second press"
echo "PASS: second press stops the sound"

# 2. Play button next to the first segment starts the sound from the segment.
BEFORE="$(ui_log_count "$STARTED")"
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitById("history-segment-play-0", 10))
APPLESCRIPT
ui_wait_for_log_event "$STARTED" "$BEFORE" 10 || ui_fail "No play_started after the segment button"
echo "PASS: segment play button starts the sound"

# 3. The record plays, so one slider step (AX increment, like an arrow key) is a seek.
SEEKS="$(ui_log_count 'history-audio] play_seek.*source=slider')"
ui_osascript <<'APPLESCRIPT'
set theSlider to my waitByAttr("AXSlider", "AXDescription", {"Playback position", "Позиция воспроизведения"}, 10)
my requireFront()
tell application "System Events" to perform action "AXIncrement" of theSlider
APPLESCRIPT
ui_wait_for_log_event 'history-audio] play_seek.*source=slider' "$SEEKS" 10 || ui_fail "No play_seek after a slider step"
echo "PASS: slider step seeks (play_seek source=slider)"

BEFORE="$(ui_log_count 'history-audio] play_(started|seek)')"
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitById("history-segment-play-1", 10))
APPLESCRIPT
ui_wait_for_log_event 'history-audio] play_(started|seek)' "$BEFORE" 10 || ui_fail "No play_started or play_seek after the second segment button"
echo "PASS: second segment button plays from its segment"

# Slider drag, setting its value, and typing in a segment while the sound plays, are manual checks: see docs/testing.md.
ui_osascript <<'APPLESCRIPT'
my requireFront()
tell application "System Events" to click (my waitByAttr("AXButton", "AXHelp", {"Listen", "Stop", "Прослушать", "Остановить"}, 5))
APPLESCRIPT
echo "PASS: ui:history-audio"
