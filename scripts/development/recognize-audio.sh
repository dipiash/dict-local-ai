#!/usr/bin/env bash
# Usage: recognize-audio.sh <audio-file> file|meeting <output-json>
set -euo pipefail
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <audio-file> file|meeting <output-json>" >&2
  exit 2
fi
# Resolve paths before changing the working directory.
absolute() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
audio_path=$(absolute "$1")
output_path=$(absolute "$3")
cd "$(dirname "$0")/../.."

/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon --arch arm64 --product DictLocalAI >&2
binary_dir=$(/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon --arch arm64 --show-bin-path)

DICT_CODE_SHA=$(git rev-parse HEAD 2>/dev/null || echo unknown)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then DICT_CODE_DIRTY=1; else DICT_CODE_DIRTY=0; fi
export DICT_CODE_SHA DICT_CODE_DIRTY
exec /usr/bin/arch -arm64 "$binary_dir/DictLocalAI" --recognize-audio "$audio_path" --recognition-mode "$2" --report-json "$output_path"
