#!/bin/bash
DICT_TCC_BUNDLE_ID='app.dictlocalai.desktop'
DICT_TCC_APP_NAME='Dict Local AI.app'
# The permission doctor uses this value.
# shellcheck disable=SC2034
DICT_TCC_INSTALL_PATH="$HOME/Applications/$DICT_TCC_APP_NAME"

dict_tcc_requirement() {
  local app="$1" requirement
  requirement=$(/usr/bin/codesign -d -r- "$app" 2>&1) || return 1
  printf '%s\n' "$requirement" | /usr/bin/sed -n 's/^[[:space:]]*designated =>[[:space:]]*//p' | /usr/bin/head -n 1
}

dict_tcc_assert_stable_signature() {
  local app="$1" actual_id requirement
  [[ -d "$app" ]] || { echo "App not found: $app" >&2; return 1; }
  /usr/bin/codesign --verify --deep --strict "$app" || return 1
  actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") || return 1
  if [[ "$actual_id" != "$DICT_TCC_BUNDLE_ID" ]]; then
    echo "Unexpected bundle ID: $actual_id (expected $DICT_TCC_BUNDLE_ID)" >&2
    return 1
  fi
  requirement=$(dict_tcc_requirement "$app") || return 1
  if [[ -z "$requirement" || "$requirement" == *'cdhash '* || "$requirement" != *'identifier '* || ( "$requirement" != *'anchor '* && "$requirement" != *'certificate '* ) ]]; then
    echo "TCC: the signature lacks a stable identity: $app" >&2
    echo "Designated Requirement: $requirement" >&2
    echo 'Create a persistent local certificate: task signing:setup' >&2
    return 1
  fi
  if /usr/bin/codesign -dv "$app" 2>&1 | /usr/bin/grep -q 'Signature=adhoc'; then
    echo 'TCC: ad-hoc signing is unsupported.' >&2
    return 1
  fi
}

dict_tcc_check_upgrade() {
  local previous="$1" replacement="$2" old_req new_req work
  [[ -d "$previous" ]] || return 0
  dict_tcc_assert_stable_signature "$previous" || {
    echo 'The installed copy lacks a stable signature. Use task uninstall before reinstalling and granting permissions again.' >&2
    return 1
  }
  dict_tcc_assert_stable_signature "$replacement" || return 1
  old_req=$(dict_tcc_requirement "$previous") || return 1
  new_req=$(dict_tcc_requirement "$replacement") || return 1
  if [[ "$old_req" != "$new_req" ]]; then
    echo 'TCC: The designated requirement changed. Update stopped.' >&2
    echo "Existing requirement: $old_req" >&2
    echo "New requirement:  $new_req" >&2
    return 1
  fi
  work=$(/usr/bin/mktemp -d) || return 1
  printf '%s\n' "$old_req" > "$work/old.req"
  printf '%s\n' "$new_req" > "$work/new.req"
  if ! /usr/bin/codesign --verify -R "$work/old.req" "$replacement" >/dev/null 2>&1 ||
     ! /usr/bin/codesign --verify -R "$work/new.req" "$previous" >/dev/null 2>&1; then
    /bin/rm -rf "$work"
    echo 'TCC: the new app does not meet the existing code requirement. Update stopped.' >&2
    return 1
  fi
  /bin/rm -rf "$work"
  echo 'TCC: signing identity and permissions preserved.'
}
