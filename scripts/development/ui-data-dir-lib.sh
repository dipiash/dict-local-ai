#!/usr/bin/env bash
# Source these helpers to run desktop scenarios against temporary data.
# It never touches the user's data: the app runs with DICT_DATA_DIR and DICT_LOG_DIR in a temp folder.
APP="${DICT_APP_PATH:-$HOME/Applications/Dict Local AI.app}"
APP_BIN="$APP/Contents/MacOS/DictLocalAI"
USER_LOG_DIR="$HOME/Library/Logs/Dict Local AI"
UI_ROOT=""
UI_DATA=""
UI_LOGS=""
UI_PID=""
UI_LOG_FILE=""
UI_WAS_RUNNING=0
UI_CLEANUP_HOOK=""

ui_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# The data folder must be a fresh folder inside the temp area, never inside the user's Library.
ui_assert_temp_dir() {
  local path real temp
  path="$1"
  [[ -d "$path" ]] || ui_fail "Data folder does not exist: $path"
  real="$(cd "$path" && pwd -P)"
  temp="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  case "$real" in
    "$temp"/dict-ui-*) ;;
    /private/tmp/dict-ui-* | /tmp/dict-ui-*) ;;
    *) ui_fail "DICT_DATA_DIR must be a dict-ui-* folder inside the temp folder, got: $real" ;;
  esac
  case "$real" in
    *"/Library/"*) ui_fail "DICT_DATA_DIR must not be inside a Library folder: $real" ;;
  esac
}

ui_require_environment() {
  [[ "$(uname -s)" == Darwin ]] || ui_fail "macOS required"
  [[ -x "$APP_BIN" ]] || ui_fail "App not found: $APP"
  # Require a build that honors DICT_DATA_DIR before running against test fixtures.
  strings -a "$APP_BIN" | grep -c 'data_dir=override' >/dev/null \
    || ui_fail "The installed app does not support DICT_DATA_DIR. Install a new build first."
}

# Prints "busy" when the log of a running app shows a recording or a meeting in progress.
ui_session_busy() {
  local pid log
  pid="$1"
  log="$(find "$USER_LOG_DIR" -maxdepth 1 -name "session-*-$pid.log" 2>/dev/null | head -1)"
  [[ -n "$log" ]] || {
    echo "unknown"
    return
  }
  awk '
    $2 == "[meeting]" && ($3 == "start" || $3 == "stop" || $3 == "finished") { meeting = $3 }
    $2 == "[dictation]" && ($3 == "start" || $3 == "models_ready" || $3 ~ /^microphone_start/ \
      || $3 == "finish" || $3 == "recognition_finishing" || $3 == "decoded" || $3 == "completed" \
      || $3 == "cancel" || $3 == "interrupted" || $3 == "start_failed" || $3 == "notice" \
      || $3 == "recognition_failed" || $3 == "cancel_preparation_by_toggle") { dictation = $3 }
    END {
      busy = (meeting == "start" || meeting == "stop")
      if (dictation == "start" || dictation == "models_ready" || dictation ~ /^microphone_start/ \
        || dictation == "finish" || dictation == "recognition_finishing") { busy = 1 }
      print busy ? "busy" : "idle"
    }' "$log"
}

ui_quit_regular_app() {
  local pid state
  pid="$(pgrep -x DictLocalAI | head -1 || true)"
  [[ -n "$pid" ]] || return 0
  state="$(ui_session_busy "$pid")"
  case "$state" in
    busy) ui_fail "A recording or a meeting is in progress in the running app. Not closing it." ;;
    unknown) ui_fail "Cannot read the session log of the running app (pid $pid). Not closing it." ;;
  esac
  UI_WAS_RUNNING=1
  osascript -e 'tell application "Dict Local AI" to quit' >/dev/null 2>&1 || true
  local waited=0
  while pgrep -x DictLocalAI >/dev/null; do
    sleep 0.5
    waited=$((waited + 1))
    [[ "$waited" -le 30 ]] || ui_fail "The running app did not quit in 15 s (unsaved changes?). Quit it yourself and run again."
  done
}

ui_make_fixture() {
  local text
  text="The first sample describes the weather. The second sample describes a green table. The third sample describes a quiet river."
  say -o "$UI_ROOT/fixture.aiff" "$text"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$UI_ROOT/fixture.aiff" "$UI_ROOT/fixture.wav"
}

ui_seed_history() {
  DICT_DATA_DIR="$UI_DATA" DICT_LOG_DIR="$UI_LOGS" "$APP_BIN" --add-history-fixture "$UI_ROOT/fixture.wav" \
    --transcript-line "The first sample describes the weather." \
    --transcript-line "The second sample describes a green table." \
    --transcript-line "The third sample describes a quiet river." \
    || ui_fail "Seeding the test history failed"
}

ui_stop_test_app() {
  [[ -n "$UI_PID" ]] || return 0
  if kill -0 "$UI_PID" 2>/dev/null; then
    osascript -e 'tell application "Dict Local AI" to quit' >/dev/null 2>&1 || true
    local waited=0
    while kill -0 "$UI_PID" 2>/dev/null && [[ "$waited" -lt 20 ]]; do
      sleep 0.5
      waited=$((waited + 1))
    done
    # The test copy only holds throw-away data, so a forced stop is safe here.
    kill -0 "$UI_PID" 2>/dev/null && kill -TERM "$UI_PID" 2>/dev/null
    sleep 1
    kill -0 "$UI_PID" 2>/dev/null && kill -KILL "$UI_PID" 2>/dev/null
  fi
  UI_PID=""
}

ui_cleanup() {
  local status=$?
  trap - EXIT INT TERM
  [[ -z "$UI_CLEANUP_HOOK" ]] || "$UI_CLEANUP_HOOK" || true
  ui_stop_test_app
  if [[ -n "$UI_ROOT" && -d "$UI_ROOT" ]]; then
    if [[ "$status" -ne 0 ]]; then
      local saved
      saved="$USER_LOG_DIR/ui-tests/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$saved" && cp "$UI_LOGS"/*.log "$saved"/ 2>/dev/null || true
      echo "Test folder kept: $UI_ROOT" >&2
      echo "Logs of the test copy saved to: $saved" >&2
    elif [[ "${UI_KEEP:-0}" == 1 ]]; then
      echo "UI_KEEP=1, test folder kept: $UI_ROOT" >&2
    else
      (ui_assert_temp_dir "$UI_ROOT") && rm -rf "$UI_ROOT"
    fi
  fi
  if [[ "$UI_WAS_RUNNING" == 1 ]]; then open "$APP" || true; fi
  exit "$status"
}

# Launch the isolated app with fixture data and wait for its window.
ui_start() {
  ui_require_environment
  UI_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dict-ui-XXXXXX")"
  UI_DATA="$UI_ROOT/data"
  UI_LOGS="$UI_ROOT/ui-test-logs"
  mkdir -p "$UI_DATA" "$UI_LOGS"
  trap ui_cleanup EXIT INT TERM
  ui_assert_temp_dir "$UI_DATA"
  ui_assert_temp_dir "$UI_LOGS"
  ui_quit_regular_app
  ui_make_fixture
  ui_seed_history
  touch "$UI_ROOT/launched"
  open -n -a "$APP" --env "DICT_DATA_DIR=$UI_DATA" --env "DICT_LOG_DIR=$UI_LOGS"
  local waited=0
  while [[ -z "$UI_LOG_FILE" ]]; do
    UI_LOG_FILE="$(find "$UI_LOGS" -maxdepth 1 -name 'session-*.log' -newer "$UI_ROOT/launched" | head -1)"
    sleep 0.5
    waited=$((waited + 1))
    [[ "$waited" -le 60 || -n "$UI_LOG_FILE" ]] || ui_fail "The test app did not start (no session log in 30 s)"
  done
  UI_PID="$(basename "$UI_LOG_FILE" .log)"
  UI_PID="${UI_PID##*-}"
  # Verify that the data override is active before manipulating the app.
  ui_wait_for_log_event 'data_dir=override' 0 20 || ui_fail "The test app does not use DICT_DATA_DIR"
  waited=0
  until osascript -e 'tell application "System Events" to tell process "Dict Local AI" to count of windows' 2>/dev/null | grep -qv '^0$'; do
    sleep 0.5
    waited=$((waited + 1))
    [[ "$waited" -le 40 ]] || ui_fail "No workspace window of the test app in 20 s (Accessibility access?)"
  done
}

ui_log_count() { grep -Ec -- "$1" "$UI_LOG_FILE" || true; }

# ui_wait_for_log_event <pattern> <count before> <seconds>: waits until the pattern has more lines than before.
ui_wait_for_log_event() {
  local waited=0 limit=$(($3 * 2))
  while [[ "$(ui_log_count "$1")" -le "$2" ]]; do
    sleep 0.5
    waited=$((waited + 1))
    [[ "$waited" -le "$limit" ]] || return 1
  done
}

# Runs the AppleScript from stdin together with the shared handlers.
ui_osascript() {
  local body
  body="$(cat)"
  osascript -e "property uiPid : $UI_PID" -e "$UI_AS_HELPERS" -e "$body" >/dev/null
}

read -r -d '' UI_AS_HELPERS <<'APPLESCRIPT' || true
on attrOf(el, attrName)
  tell application "System Events"
    try
      if attrName is "AXTitle" then return (title of el) as text
      if attrName is "AXDescription" then return (description of el) as text
      if attrName is "AXValue" then return (value of el) as text
    end try
  end tell
  return ""
end attrOf

on findById(ident)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      repeat with uiItem in els
        try
          if (value of attribute "AXIdentifier" of uiItem) is ident then return uiItem
        end try
      end repeat
    end tell
  end tell
  return missing value
end findById

on waitById(ident, secs)
  repeat (secs * 2) times
    set el to my findById(ident)
    if el is not missing value then return el
    delay 0.5
  end repeat
  error "Element not found: " & ident
end waitById

on findByRoleAndText(roleName, needles)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      repeat with uiItem in els
        try
          if (value of attribute "AXRole" of uiItem) is roleName then
            set texts to {my attrOf(uiItem, "AXTitle"), my attrOf(uiItem, "AXDescription"), my attrOf(uiItem, "AXValue")}
            repeat with needle in needles
              repeat with t in texts
                if (t as text) contains (needle as text) then return uiItem
              end repeat
            end repeat
          end if
        end try
      end repeat
    end tell
  end tell
  return missing value
end findByRoleAndText

on waitForText(needles, secs)
  repeat (secs * 2) times
    set texts to {}
    tell application "System Events"
      tell process "Dict Local AI"
        set els to entire contents of front window
        repeat with uiItem in els
          try
            set end of texts to (name of uiItem as text)
          end try
          try
            set end of texts to (value of uiItem as text)
          end try
        end repeat
      end tell
    end tell
    repeat with t in texts
      repeat with needle in needles
        if (t as text) contains (needle as text) then return true
      end repeat
    end repeat
    delay 0.5
  end repeat
  return false
end waitForText

on requireText(needles, secs, what)
  if not my waitForText(needles, secs) then error "Missing on screen: " & what
end requireText

on clickCenter(el)
  tell application "System Events"
    set {px, py} to position of el
    set {sw, sh} to size of el
    my requireFront()
    click at {px + (sw / 2), py + (sh / 2)}
  end tell
end clickCenter

on clickText(needles)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      repeat with uiItem in els
        try
          if (role of uiItem) is "AXOutline" then
            repeat with r in (rows of uiItem)
              try
                set t to (value of static text 1 of UI element 1 of r) as text
                repeat with needle in needles
                  if t contains (needle as text) then
                    set selected of r to true
                    return
                  end if
                end repeat
              end try
            end repeat
          end if
        end try
      end repeat
    end tell
  end tell
  error "Row not found: " & (item 1 of needles)
end clickText

-- The switch has no name of its own: it is the check box that follows its label text.
on findSwitchAfterText(needles)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      set total to count of els
      repeat with i from 1 to total
        try
          set uiItem to item i of els
          if (role of uiItem) is "AXStaticText" then
            repeat with needle in needles
              if (value of uiItem as text) is (needle as text) then
                repeat with j from (i + 1) to total
                  if (role of (item j of els)) is "AXCheckBox" then return item j of els
                end repeat
              end if
            end repeat
          end if
        end try
      end repeat
    end tell
  end tell
  return missing value
end findSwitchAfterText

-- Some SwiftUI controls do not export their identifier, so they are found by an AX attribute.
on findByAttr(roleName, attrName, needles)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      repeat with uiItem in els
        try
          if (value of attribute "AXRole" of uiItem) is roleName then
            set v to (value of attribute attrName of uiItem) as text
            repeat with needle in needles
              if v is (needle as text) then return contents of uiItem
            end repeat
          end if
        end try
      end repeat
    end tell
  end tell
  return missing value
end findByAttr

on waitByAttr(roleName, attrName, needles, secs)
  repeat (secs * 2) times
    set el to my findByAttr(roleName, attrName, needles)
    if el is not missing value then return el
    delay 0.5
  end repeat
  error "Element not found by " & attrName & ": " & (item 1 of needles)
end waitByAttr

on findTextFieldWith(needle)
  tell application "System Events"
    tell process "Dict Local AI"
      set els to entire contents of front window
      repeat with uiItem in els
        try
          if (role of uiItem) is "AXTextField" and ((value of uiItem as text) contains needle) then return contents of uiItem
        end try
      end repeat
    end tell
  end tell
  return missing value
end findTextFieldWith

on isFront()
  tell application "System Events"
    return (unix id of first process whose frontmost is true) is uiPid
  end tell
end isFront

-- Keys and clicks go to the active app, so stop instead of typing into someone else's window.
on requireFront()
  if not my isFront() then error "Test window is not active: the test copy lost the focus, nothing was typed"
end requireFront

on ensureFront()
  repeat 20 times
    tell application "System Events"
      set frontmost of (first process whose unix id is uiPid) to true
    end tell
    if my isFront() then return
    delay 0.5
  end repeat
  error "Test window is not active: the test copy did not come to the front"
end ensureFront

on openSection(key, needles, what)
  repeat 3 times
    my ensureFront()
    delay 0.5
    my requireFront()
    tell application "System Events" to keystroke key using {command down}
    if my waitForText(needles, 4) then return
  end repeat
  error "Missing on screen: " & what
end openSection
APPLESCRIPT
