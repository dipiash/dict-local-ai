#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
log_dir="${DICT_LOG_DIR:-$HOME/Library/Logs/Dict Local AI}"
mkdir -p "$log_dir"
pid=$(pgrep -n -x DictLocalAI || true)
if [[ -z "$pid" ]]; then
  echo 'DictLocalAI process not found.' >&2
  exit 1
fi
stamp=$(date +%Y%m%d-%H%M%S)
echo "PID: $pid"
echo "Capturing main and worker threads (may request admin approval)..."
/usr/bin/sample "$pid" 10 -file "$log_dir/hang-$stamp.sample.txt" || true
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "app.dictlocalai"'   > "$log_dir/unified-$stamp.log" || true
printf 'Reports: %s/hang-%s.sample.txt and %s/unified-%s.log\n' "$log_dir" "$stamp" "$log_dir" "$stamp"
