#!/usr/bin/env bash
set -euo pipefail
log_dir="${DICT_LOG_DIR:-$HOME/Library/Logs/Dict Local AI}"
if [[ ! -d "$log_dir" ]]; then
  printf 'Log directory not found: %s\n' "$log_dir" >&2
  exit 1
fi
log_file="$(find "$log_dir" -maxdepth 1 -type f -name 'session-*.log' -print | sort -r | head -n 1)"
if [[ -z "$log_file" ]]; then
  printf 'No session-*.log files found: %s\n' "$log_dir" >&2
  exit 1
fi
printf 'Log: %s\n' "$log_file"
printf 'Navigation and action events (last 120 lines):\n'
grep -E '\[usage\]|\[navigation\]' "$log_file" | tail -n 120 || true
